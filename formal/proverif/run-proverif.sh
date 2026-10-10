#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${HERE}/../.." && pwd)"
TOOL_ROOT="${REPO_ROOT}/.formal-tools"
PROVERIF="${PROVERIF_BIN:-${TOOL_ROOT}/proverif2.05/proverif}"
PROVERIF="$(readlink -f "$(command -v "${PROVERIF}")")"
SOURCE_ARCHIVE="${TOOL_ROOT}/proverif2.05.tar.gz"
EXPECTED_SOURCE_SHA="4871f53c32ab4a04669a060c4886ba5d9080496963fb980a9a62d2c429ceabc4"
test -x "${PROVERIF}" || { echo "missing ProVerif executable" >&2; exit 2; }
actual_source_sha="unavailable (external build)"
if [[ -f "${SOURCE_ARCHIVE}" ]]; then
  actual_source_sha="$(sha256sum "${SOURCE_ARCHIVE}" | awk '{print $1}')"
  test "${actual_source_sha}" = "${EXPECTED_SOURCE_SHA}" || {
    echo "ProVerif source archive SHA256 mismatch" >&2; exit 2;
  }
fi
actual_binary_sha="$(sha256sum "${PROVERIF}" | awk '{print $1}')"
PROVERIF_HELP="$("${PROVERIF}" -help 2>&1)"
grep -F "Proverif 2.05." <<<"${PROVERIF_HELP}" >/dev/null
command -v node >/dev/null
command -v timeout >/dev/null

node "${HERE}/generate-mutants.mjs" >/dev/null

stamp="$(date -u +%Y%m%dT%H%M%SZ)"
RUN_DIR="${PROVERIF_OUTPUT_ROOT:-${REPO_ROOT}/evidence/proverif}/proverif-${stamp}"
test ! -e "${RUN_DIR}" || { echo "run directory already exists" >&2; exit 2; }
RAW_DIR="${RUN_DIR}/raw"
SOURCE_DIR="${RUN_DIR}/source/formal/proverif"
TOOLCHAIN_DIR="${RUN_DIR}/toolchain"
mkdir -p "${RAW_DIR}" "${SOURCE_DIR}" "${TOOLCHAIN_DIR}"
printf 'RUNNING\n' > "${RUN_DIR}/RUN-STATUS.txt"
mark_failed_on_exit() {
  rc=$?
  if [[ ${rc} -ne 0 ]]; then
    printf 'FAIL rc=%s\n' "${rc}" > "${RUN_DIR}/RUN-STATUS.txt"
  fi
}
trap mark_failed_on_exit EXIT

model_ids=(
  auth-binding
  settlement
  compromise
  auth-reachability
  mutant-device-origin-bypass
  mutant-policy-version-unbound
  mutant-payer-provider-unbound
  mutant-settlement-unkeyed-consume
)
model_paths=(
  protocol-v2-auth-binding.pv
  protocol-v2-settlement.pv
  protocol-v2-compromise.pv
  protocol-v2-auth-reachability.pv
  mutants/protocol-v2-device-origin-bypass.pv
  mutants/protocol-v2-policy-version-unbound.pv
  mutants/protocol-v2-payer-provider-unbound.pv
  mutants/protocol-v2-settlement-unkeyed-consume.pv
)
timeouts=(120 120 120 120 120 120 120 120)

for index in "${!model_ids[@]}"; do
  model_id="${model_ids[$index]}"
  model_path="${model_paths[$index]}"
  timeout_sec="${timeouts[$index]}"
  stdout_file="${RAW_DIR}/${model_id}.stdout.log"
  stderr_file="${RAW_DIR}/${model_id}.stderr.log"
  command_file="${RAW_DIR}/${model_id}.command.txt"
  metrics_file="${RAW_DIR}/${model_id}.metrics.json"
  model_sha="$(sha256sum "${HERE}/${model_path}" | awk '{print $1}')"

  printf 'timeout --signal=TERM --kill-after=5s %ss %q %q\n' \
    "${timeout_sec}" "proverif" "${model_path}" > "${command_file}"
  started_ms="$(date +%s%3N)"
  set +e
  (cd "${HERE}" && timeout --signal=TERM --kill-after=5s "${timeout_sec}s" \
    "${PROVERIF}" "${model_path}") \
    >"${stdout_file}" 2>"${stderr_file}"
  rc=$?
  set -e
  ended_ms="$(date +%s%3N)"
  elapsed_ms="$((ended_ms - started_ms))"
  printf '{\n  "modelId": "%s",\n  "modelPath": "%s",\n  "modelSha256": "%s",\n  "timeoutSec": %s,\n  "rc": %s,\n  "elapsedMs": %s\n}\n' \
    "${model_id}" "${model_path}" "${model_sha}" "${timeout_sec}" "${rc}" "${elapsed_ms}" \
    > "${metrics_file}"
done

cp "${HERE}"/*.pv "${SOURCE_DIR}/"
cp "${HERE}"/*.md "${SOURCE_DIR}/" 2>/dev/null || true
cp "${HERE}"/*.json "${SOURCE_DIR}/"
cp "${HERE}"/*.mjs "${SOURCE_DIR}/"
cp "${HERE}"/*.sh "${SOURCE_DIR}/"
mkdir -p "${SOURCE_DIR}/mutants"
cp "${HERE}"/mutants/*.pv "${SOURCE_DIR}/mutants/"
printf '%s\n' 'https://proverif.inria.fr/proverif2.05.tar.gz' > "${TOOLCHAIN_DIR}/source-url.txt"
printf '%s  %s\n' "${actual_source_sha}" '.formal-tools/proverif2.05.tar.gz' > "${TOOLCHAIN_DIR}/source-archive.sha256"
printf '%s  %s\n' "${actual_binary_sha}" 'proverif' > "${TOOLCHAIN_DIR}/binary.sha256"
printf '%s\n' "${PROVERIF_HELP%%$'\n'*}" > "${TOOLCHAIN_DIR}/version.txt"
node "${HERE}/summarize-results.mjs" \
  "${HERE}/expected-results.json" \
  "${RAW_DIR}" \
  "${RUN_DIR}/summary.json" \
  "${RUN_DIR}/summary.tsv"

{
  printf 'utc=%s\n' "$(date -u --iso-8601=seconds)"
  printf 'uname=%s\n' "$(uname -sm)"
  printf 'node=%s\n' "$(node --version)"
  printf 'proverif=%s\n' "${PROVERIF_HELP%%$'\n'*}"
} > "${RUN_DIR}/environment.txt"

(
  cd "${RUN_DIR}"
  find source -type f -print0 | sort -z | xargs -0 sha256sum
) > "${RUN_DIR}/source-manifest.sha256"
(
  cd "${RUN_DIR}"
  sha256sum -c source-manifest.sha256
) > "${RUN_DIR}/source-manifest.verify.txt"
(
  cd "${RUN_DIR}"
  sha256sum source-manifest.sha256 source-manifest.verify.txt
) > "${RUN_DIR}/source-seal.sha256"

set +e
node - "${RUN_DIR}" > "${RUN_DIR}/secret-scan.txt" <<'NODE'
const fs = require("node:fs");
const path = require("node:path");
const root = process.argv[2];
const patterns = [
  ["private-key-block", new RegExp("BEGIN\\s+.*PRIVATE" + " KEY", "i")],
  ["password-assignment", new RegExp("pass" + "word\\s*[:=]", "i")],
  ["api-key-assignment", new RegExp("api[_-]?" + "key\\s*[:=]", "i")],
  ["mnemonic-assignment", new RegExp("mnemo" + "nic\\s*[:=]", "i")],
  ["noninteractive-ssh-secret", new RegExp("ssh" + "pass", "i")],
];
const excluded = new Set(["secret-scan.txt"]);
const findings = [];
function visit(directory) {
  for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
    const full = path.join(directory, entry.name);
    if (entry.isDirectory()) visit(full);
    else if (!excluded.has(entry.name)) {
      const data = fs.readFileSync(full);
      if (data.includes(0)) continue;
      const text = data.toString("utf8");
      for (const [id, pattern] of patterns) {
        if (pattern.test(text)) findings.push(`${id}\t${path.relative(root, full)}`);
      }
    }
  }
}
visit(root);
if (findings.length) {
  process.stdout.write(`${findings.join("\n")}\n`);
  process.exitCode = 1;
} else {
  process.stdout.write("PASS: no prohibited credential pattern found.\n");
}
NODE
secret_scan_rc=$?
set -e
if [[ ${secret_scan_rc} -ne 0 ]]; then
  echo "secret scan found a prohibited pattern or failed rc=${secret_scan_rc}" >&2
  exit 3
fi

printf 'PASS\n' > "${RUN_DIR}/RUN-STATUS.txt"

(
  cd "${RUN_DIR}"
  find . -type f \
    ! -name 'manifest.sha256' \
    ! -name 'manifest.verify.txt' \
    ! -name 'seal.sha256' \
    -printf '%P\0' | sort -z | xargs -0 sha256sum
) > "${RUN_DIR}/manifest.sha256"
(
  cd "${RUN_DIR}"
  sha256sum -c manifest.sha256
) > "${RUN_DIR}/manifest.verify.txt"
(
  cd "${RUN_DIR}"
  sha256sum manifest.sha256 manifest.verify.txt summary.json source-seal.sha256
) > "${RUN_DIR}/seal.sha256"

printf '%s\n' "${RUN_DIR}"
trap - EXIT
