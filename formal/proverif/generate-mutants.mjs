#!/usr/bin/env node
/* Deterministically derives the full unkeyed-consumption mutant from the
 * positive settlement model. Every replacement is cardinality checked so a
 * source drift fails closed instead of silently producing a different model.
 */
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const sourcePath = path.join(here, "protocol-v2-settlement.pv");
const outputPath = path.join(
  here,
  "mutants",
  "protocol-v2-settlement-unkeyed-consume.pv",
);

let source = fs.readFileSync(sourcePath, "utf8");
const replacements = [
  [
    "(* Protocol v2 -- ProVerif 2.05 relay/settlement correspondence module.",
    "(* EXPECTED-FAILING MUTANT: unkeyed settlement-consumption capability.\n   This deliberately removes the exact-order key from the one-shot process,\n   allowing attempts created for distinct authorizations to consume the same\n   public order. The injective settlement correspondence must be false.\n\n   Derived from protocol-v2-settlement.pv by generate-mutants.mjs.\n\n   Protocol v2 -- ProVerif 2.05 relay/settlement correspondence module.",
  ],
  [
    "let SettlementAttempt(expectedOrder:bitstring) =\n  in(net,(=expectedOrder,payerSig:bitstring,cert:bitstring,",
    "let SettlementAttempt() =\n  in(net,(expectedOrder:bitstring,payerSig:bitstring,cert:bitstring,",
  ],
  ["  SettlementAttempt(order).", "  SettlementAttempt()."],
];

for (const [before, after] of replacements) {
  const first = source.indexOf(before);
  const second = first < 0 ? -1 : source.indexOf(before, first + before.length);
  if (first < 0 || second >= 0) {
    throw new Error(
      `Expected exactly one source fragment, found ${first < 0 ? 0 : 2}: ${before}`,
    );
  }
  source = source.replace(before, after);
}

fs.mkdirSync(path.dirname(outputPath), { recursive: true });
fs.writeFileSync(outputPath, source, "utf8");
process.stdout.write(`${outputPath}\n`);
