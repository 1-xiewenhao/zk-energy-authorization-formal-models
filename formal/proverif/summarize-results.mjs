#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";

const [expectedPath, rawDir, jsonOutput, tsvOutput] = process.argv.slice(2);
if (!expectedPath || !rawDir || !jsonOutput || !tsvOutput) {
  throw new Error(
    "usage: node summarize-results.mjs EXPECTED_JSON RAW_DIR SUMMARY_JSON SUMMARY_TSV",
  );
}

const expected = JSON.parse(fs.readFileSync(expectedPath, "utf8"));
const records = [];
const modelRecords = [];

function observedStatus(line) {
  if (/ is true\.$/.test(line)) return "TRUE";
  if (/ is false\.$/.test(line)) return "FALSE";
  if (/ cannot be proved\.$/.test(line)) return "UNKNOWN";
  return "UNPARSED";
}

for (const model of expected.models) {
  const stdoutPath = path.join(rawDir, `${model.id}.stdout.log`);
  const stderrPath = path.join(rawDir, `${model.id}.stderr.log`);
  const metricsPath = path.join(rawDir, `${model.id}.metrics.json`);
  const stdout = fs.existsSync(stdoutPath) ? fs.readFileSync(stdoutPath, "utf8") : "";
  const stderr = fs.existsSync(stderrPath) ? fs.readFileSync(stderrPath, "utf8") : "";
  const metrics = fs.existsSync(metricsPath)
    ? JSON.parse(fs.readFileSync(metricsPath, "utf8"))
    : { rc: null, elapsedMs: null, timeoutSec: model.timeoutSec };
  const timedOut = metrics.rc === 124 || metrics.rc === 137;
  const commandError = metrics.rc !== 0 && !timedOut;
  const traceFound = /A trace has been found\./.test(stdout);
  const resultLines = stdout
    .split(/\r?\n/)
    .filter((line) => line.startsWith("RESULT "))
    .filter((line) => !line.startsWith("RESULT (but "));
  const consumed = new Set();

  let modelPass = !timedOut && !commandError;
  for (const property of model.properties) {
    const selectorCount = Number(Boolean(property.queryPrefix)) + Number(Boolean(property.queryRegex));
    if (selectorCount !== 1) {
      throw new Error(`${model.id}/${property.id} must define exactly one queryPrefix or queryRegex`);
    }
    const queryRegex = property.queryRegex ? new RegExp(property.queryRegex) : null;
    const matches = resultLines
      .map((line, index) => ({ line, index }))
      .filter(({ line }) => property.queryPrefix
        ? line.startsWith(property.queryPrefix)
        : queryRegex.test(line));
    let observed;
    let query = null;
    let propertyPass = false;
    let diagnostic = "";

    if (timedOut) {
      observed = "TIMEOUT";
      diagnostic = `process exceeded ${metrics.timeoutSec}s`;
    } else if (commandError) {
      observed = "ERROR";
      diagnostic = `ProVerif exited rc=${metrics.rc}: ${stderr.trim()}`;
    } else if (matches.length === 0) {
      observed = "MISSING";
      diagnostic = "no RESULT line matched the exact prefix/regex selector";
    } else if (matches.length > 1) {
      observed = "AMBIGUOUS";
      diagnostic = `${matches.length} RESULT lines matched the exact prefix/regex selector`;
    } else {
      query = matches[0].line;
      consumed.add(matches[0].index);
      observed = observedStatus(query);
      propertyPass = observed === property.expected;
      if (!propertyPass) diagnostic = `expected ${property.expected}, observed ${observed}`;
    }

    if (!propertyPass) modelPass = false;
    records.push({
      modelId: model.id,
      modelKind: model.kind,
      propertyId: property.id,
      classification: property.classification,
      expected: property.expected,
      observed,
      pass: propertyPass,
      query,
      diagnostic,
      elapsedMs: metrics.elapsedMs,
      rc: metrics.rc,
    });
  }

  const unexpectedResults = resultLines.filter((_, index) => !consumed.has(index));
  if (unexpectedResults.length > 0) modelPass = false;
  if (model.requireTrace && !traceFound) modelPass = false;
  modelRecords.push({
    id: model.id,
    path: model.path,
    kind: model.kind,
    pass: modelPass,
    rc: metrics.rc,
    elapsedMs: metrics.elapsedMs,
    timeoutSec: metrics.timeoutSec,
    timedOut,
    traceRequired: Boolean(model.requireTrace),
    traceFound,
    unexpectedResults,
    stderrBytes: Buffer.byteLength(stderr),
  });
}

const counts = {
  true: records.filter((r) => r.observed === "TRUE").length,
  false: records.filter((r) => r.observed === "FALSE").length,
  unknown: records.filter((r) => r.observed === "UNKNOWN").length,
  timeout: records.filter((r) => r.observed === "TIMEOUT").length,
  error: records.filter((r) => r.observed === "ERROR").length,
  missingOrAmbiguous: records.filter((r) => ["MISSING", "AMBIGUOUS", "UNPARSED"].includes(r.observed)).length,
  positiveSecurityTrue: records.filter(
    (r) => ["security", "secrecy", "compromise-aware-secrecy"].includes(r.classification) && r.observed === "TRUE",
  ).length,
  reachabilityExpectedFalse: records.filter(
    (r) => r.classification === "reachability-expected-false" && r.observed === "FALSE",
  ).length,
  mutantExpectedFalse: records.filter(
    (r) => r.classification === "mutant-expected-false" && r.observed === "FALSE",
  ).length,
};

const summary = {
  schemaVersion: 1,
  generatedAt: new Date().toISOString(),
  tool: expected.tool,
  overallStatus: modelRecords.every((m) => m.pass) ? "PASS" : "FAIL",
  failClosedPolicy: {
    positiveSecurity: "only TRUE passes; FALSE/UNKNOWN/TIMEOUT/ERROR fail",
    reachability: "the negated event query must be FALSE and include a trace",
    mutants: "the named security query must be FALSE and include an attack trace",
    unexpectedResultLines: "fail",
  },
  counts,
  models: modelRecords,
  properties: records,
};

fs.writeFileSync(jsonOutput, `${JSON.stringify(summary, null, 2)}\n`, "utf8");
const tsvHeader = [
  "model_id",
  "model_kind",
  "property_id",
  "classification",
  "expected",
  "observed",
  "pass",
  "elapsed_ms",
  "rc",
  "query",
  "diagnostic",
];
const escapeTsv = (value) => String(value ?? "").replace(/[\t\r\n]+/g, " ");
const tsvRows = records.map((record) => [
  record.modelId,
  record.modelKind,
  record.propertyId,
  record.classification,
  record.expected,
  record.observed,
  record.pass,
  record.elapsedMs,
  record.rc,
  record.query,
  record.diagnostic,
].map(escapeTsv).join("\t"));
fs.writeFileSync(tsvOutput, `${tsvHeader.join("\t")}\n${tsvRows.join("\n")}\n`, "utf8");

process.stdout.write(`${summary.overallStatus}\n`);
if (summary.overallStatus !== "PASS") process.exitCode = 1;
