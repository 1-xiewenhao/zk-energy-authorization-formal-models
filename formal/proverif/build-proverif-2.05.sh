#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${HERE}/../.." && pwd)"
TOOL_ROOT="${REPO_ROOT}/.formal-tools"
ARCHIVE="${TOOL_ROOT}/proverif2.05.tar.gz"
DEST="${TOOL_ROOT}/proverif2.05"
URL="https://proverif.inria.fr/proverif2.05.tar.gz"
EXPECTED_SHA="4871f53c32ab4a04669a060c4886ba5d9080496963fb980a9a62d2c429ceabc4"

mkdir -p "${TOOL_ROOT}"
if [[ ! -f "${ARCHIVE}" ]]; then
  curl --fail --location --proto '=https' --tlsv1.2 \
    --output "${ARCHIVE}.part" "${URL}"
  mv "${ARCHIVE}.part" "${ARCHIVE}"
fi
actual_sha="$(sha256sum "${ARCHIVE}" | awk '{print $1}')"
test "${actual_sha}" = "${EXPECTED_SHA}" || {
  echo "source archive SHA256 mismatch: ${actual_sha}" >&2
  exit 2
}

if [[ -x "${DEST}/proverif" ]]; then
  "${DEST}/proverif" -help 2>&1 | sed -n '1p'
  echo "existing project-local build retained: ${DEST}"
  exit 0
fi
if [[ -e "${DEST}" ]]; then
  echo "refusing to overwrite incomplete destination ${DEST}" >&2
  exit 2
fi

temp_dir="$(mktemp -d "${TOOL_ROOT}/.proverif-build.XXXXXX")"
cleanup() { rm -rf -- "${temp_dir}"; }
trap cleanup EXIT
tar -xzf "${ARCHIVE}" -C "${temp_dir}"
source_dir="${temp_dir}/proverif2.05"
test -x "${source_dir}/build"

started_ns="$(date +%s%N)"
set +e
(
  cd "${source_dir}"
  ./build -nointeract
) >"${TOOL_ROOT}/build-proverif-2.05.stdout.log" \
  2>"${TOOL_ROOT}/build-proverif-2.05.stderr.log"
rc=$?
set -e
ended_ns="$(date +%s%N)"
elapsed_ms="$(((ended_ns - started_ns) / 1000000))"
printf 'build_rc=%s\nelapsed_ms=%s\nstarted_ns=%s\nended_ns=%s\n' \
  "${rc}" "${elapsed_ms}" "${started_ns}" "${ended_ns}" \
  > "${TOOL_ROOT}/build-proverif-2.05.metrics.txt"
test "${rc}" -eq 0
test -x "${source_dir}/proverif"
mv "${source_dir}" "${DEST}"
"${DEST}/proverif" -help 2>&1 | sed -n '1p'
sha256sum "${ARCHIVE}" "${DEST}/proverif"
