#!/usr/bin/env bash
set -uo pipefail

# Tamarin's pretty-printer emits Unicode proof symbols. A POSIX/C locale makes
# the Haskell runtime abort while writing those symbols, so make the encoding
# an explicit, recorded prerequisite instead of inheriting the SSH session.
UTF8_LOCALE="${TAMARIN_UTF8_LOCALE:-C.UTF-8}"
if ! LC_ALL="$UTF8_LOCALE" locale charmap >/dev/null 2>&1; then
  printf 'ERROR: requested UTF-8 locale is unavailable: %s\n' "$UTF8_LOCALE" >&2
  exit 2
fi
export LANG="$UTF8_LOCALE"
export LC_ALL="$UTF8_LOCALE"
LOCALE_CHARMAP="$(locale charmap)"
if [[ "$LOCALE_CHARMAP" != "UTF-8" ]]; then
  printf 'ERROR: locale must provide UTF-8, got %s for %s\n' \
    "$LOCALE_CHARMAP" "$UTF8_LOCALE" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXPECTED_INPUT="${TAMARIN_EXPECTED_FILE:-$ROOT_DIR/expected.tsv}"
TAMARIN_BIN="${TAMARIN_BIN:-tamarin-prover}"
MAUDE_BIN="${MAUDE_BIN:-maude}"
RTS_CORES="${TAMARIN_RTS_CORES:-4}"
OUTPUT_ROOT="${TAMARIN_OUTPUT_ROOT:-$(cd "$ROOT_DIR/../.." && pwd)/evidence/tamarin}"
RUN_ID="${TAMARIN_RUN_ID:-$(date -u +%Y%m%dT%H%M%SZ)}"
RUN_DIR="$OUTPUT_ROOT/$RUN_ID"

PINNED_TAMARIN_VERSION='1.12.0'
PINNED_MAUDE_VERSION='3.5.1'

check_regular_file() {
  local path="$1"
  [[ -f "$path" && ! -L "$path" ]] || return 1
  [[ "$(stat -c '%h' "$path")" -eq 1 ]] || return 1
}

check_closed_regular_tree() {
  local tree="$1" entry link_count bad=0
  [[ -d "$tree" && ! -L "$tree" ]] || return 1
  while IFS= read -r -d '' entry; do
    if [[ -L "$entry" ]]; then
      printf 'ERROR: symlink rejected from source closure: %s\n' "$entry" >&2
      bad=1
    elif [[ -d "$entry" ]]; then
      :
    elif [[ -f "$entry" ]]; then
      link_count="$(stat -c '%h' "$entry")"
      if [[ "$link_count" -ne 1 ]]; then
        printf 'ERROR: hard-linked file rejected from source closure: %s (links=%s)\n' \
          "$entry" "$link_count" >&2
        bad=1
      fi
    else
      printf 'ERROR: special entry rejected from source closure: %s\n' "$entry" >&2
      bad=1
    fi
  done < <(find "$tree" -mindepth 1 -print0)
  [[ "$bad" -eq 0 ]]
}

if [[ -e "$RUN_DIR" ]]; then
  printf 'ERROR: run directory already exists; refusing to mix evidence: %s\n' "$RUN_DIR" >&2
  exit 2
fi
if [[ ! -f "$EXPECTED_INPUT" ]]; then
  printf 'ERROR: expected-results table not found: %s\n' "$EXPECTED_INPUT" >&2
  exit 2
fi
if ! command -v "$TAMARIN_BIN" >/dev/null 2>&1; then
  printf 'ERROR: tamarin executable not found: %s\n' "$TAMARIN_BIN" >&2
  exit 2
fi
if ! command -v "$MAUDE_BIN" >/dev/null 2>&1; then
  printf 'ERROR: Maude executable not found: %s\n' "$MAUDE_BIN" >&2
  exit 2
fi
if ! check_closed_regular_tree "$ROOT_DIR/models" \
   || ! check_closed_regular_tree "$ROOT_DIR/mutants"; then
  printf 'ERROR: live model source is not a closed regular-file tree.\n' >&2
  exit 2
fi
for package_file in README.md DIAGNOSTICS.md run_all.sh expected.tsv; do
  if ! check_regular_file "$ROOT_DIR/$package_file"; then
    printf 'ERROR: package input must be one non-hard-linked regular file: %s\n' \
      "$ROOT_DIR/$package_file" >&2
    exit 2
  fi
done

mkdir -p "$RUN_DIR/raw" "$RUN_DIR/source"
cp -a "$ROOT_DIR/models" "$RUN_DIR/source/models"
cp -a "$ROOT_DIR/mutants" "$RUN_DIR/source/mutants"
cp -a "$ROOT_DIR/README.md" "$RUN_DIR/source/README.md"
cp -a "$ROOT_DIR/DIAGNOSTICS.md" "$RUN_DIR/source/DIAGNOSTICS.md"
cp -a "$ROOT_DIR/run_all.sh" "$RUN_DIR/source/run_all.sh"
cp -a "$EXPECTED_INPUT" "$RUN_DIR/source/expected.tsv"
if ! check_closed_regular_tree "$RUN_DIR/source"; then
  printf 'ERROR: copied evidence source is not a closed regular-file tree.\n' >&2
  exit 2
fi

EXEC_ROOT="$RUN_DIR/source"
EXPECTED_FILE="$EXEC_ROOT/expected.tsv"
SUMMARY="$RUN_DIR/lemma-status.tsv"
MODEL_SUMMARY="$RUN_DIR/model-status.tsv"
COMMANDS="$RUN_DIR/commands.txt"
VERSIONS="$RUN_DIR/tool-versions.txt"
COMPLETENESS="$RUN_DIR/model-table-completeness.tsv"
MODEL_SET_CHECK="$RUN_DIR/model-set-completeness.diff"
OVERALL=0

TAMARIN_PATH="$(readlink -f "$(command -v "$TAMARIN_BIN")")"
MAUDE_PATH="$(readlink -f "$(command -v "$MAUDE_BIN")")"
export PATH="$(dirname "$MAUDE_PATH"):$PATH"
ACTIVE_MAUDE_PATH="$(readlink -f "$(command -v maude)")"
TAMARIN_SHA="$(sha256sum "$TAMARIN_PATH" | awk '{print $1}')"
MAUDE_SHA="$(sha256sum "$MAUDE_PATH" | awk '{print $1}')"
VERSION_OUTPUT="$RUN_DIR/raw/tamarin-version.log"
timeout 20s "$TAMARIN_PATH" --version > "$VERSION_OUTPUT" 2>&1
VERSION_RC=$?

TOOL_GATE=PASS
if [[ "$VERSION_RC" -ne 0 ]] \
   || ! grep -Fq "tamarin-prover ${PINNED_TAMARIN_VERSION}," "$VERSION_OUTPUT" \
   || ! grep -qx "Tamarin version ${PINNED_TAMARIN_VERSION}" "$VERSION_OUTPUT" \
   || ! grep -qx "Maude version ${PINNED_MAUDE_VERSION}" "$VERSION_OUTPUT" \
   || [[ "$ACTIVE_MAUDE_PATH" != "$MAUDE_PATH" ]]; then
  TOOL_GATE=FAIL
  OVERALL=1
fi

{
  printf 'run_id=%s\n' "$RUN_ID"
  printf 'started_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf 'kernel=%s\n' "$(uname -srmo)"
  printf 'locale=%s\n' "$UTF8_LOCALE"
  printf 'locale_charmap=%s\n' "$LOCALE_CHARMAP"
  printf 'tamarin_pinned_version=%s\n' "$PINNED_TAMARIN_VERSION"
  printf 'tamarin_actual_sha256=%s\n' "$TAMARIN_SHA"
  printf 'maude_pinned_version=%s\n' "$PINNED_MAUDE_VERSION"
  printf 'maude_actual_sha256=%s\n' "$MAUDE_SHA"
  printf 'version_command_rc=%s\n' "$VERSION_RC"
  printf 'tool_gate=%s\n' "$TOOL_GATE"
} > "$VERSIONS"

printf 'kind\tmodel\tlemma\texpected\tactual\trc\tmodel_elapsed_ms\tmodel_sha256\traw_log\tgate\n' > "$SUMMARY"
printf 'kind\tmodel\trc\telapsed_ms\tmodel_sha256\traw_log_sha256\twellformed\tgate\n' > "$MODEL_SUMMARY"
printf 'model\tsource_lemma_count\ttable_lemma_count\texact_name_match\n' > "$COMPLETENESS"
: > "$COMMANDS"

# Fail closed if the model set and expected-table model set differ in either direction.
find "$EXEC_ROOT/models" -type f -name '*.spthy' -printf 'models/%P\n' > "$RUN_DIR/raw/source-model-set"
find "$EXEC_ROOT/mutants" -type f -name '*.spthy' -printf 'mutants/%P\n' >> "$RUN_DIR/raw/source-model-set"
sort -u -o "$RUN_DIR/raw/source-model-set" "$RUN_DIR/raw/source-model-set"
awk -F '\t' '$1 !~ /^#/ && NF >= 5 {print $2}' "$EXPECTED_FILE" | sort -u > "$RUN_DIR/raw/table-model-set"
if ! diff -u "$RUN_DIR/raw/source-model-set" "$RUN_DIR/raw/table-model-set" > "$MODEL_SET_CHECK"; then
  OVERALL=1
fi

# Fail closed if expected.tsv omits, invents, or duplicates a lemma.
while IFS= read -r model_rel; do
  [[ -n "$model_rel" ]] || continue
  model_path="$EXEC_ROOT/$model_rel"
  safe_model="${model_rel//\//__}"
  source_names="$RUN_DIR/raw/${safe_model}.source-lemmas"
  table_names="$RUN_DIR/raw/${safe_model}.table-lemmas"
  if [[ ! -f "$model_path" ]]; then
    printf '%s\tMISSING\tMISSING\tNO\n' "$model_rel" >> "$COMPLETENESS"
    OVERALL=1
    continue
  fi
  sed -nE 's/^lemma[[:space:]]+([A-Za-z0-9_]+):.*/\1/p' "$model_path" | sort > "$source_names"
  awk -F '\t' -v model="$model_rel" '$1 !~ /^#/ && $2 == model {print $3}' "$EXPECTED_FILE" | sort > "$table_names"
  source_count="$(wc -l < "$source_names" | tr -d ' ')"
  table_count="$(wc -l < "$table_names" | tr -d ' ')"
  if diff -u "$source_names" "$table_names" > "$RUN_DIR/raw/${safe_model}.lemma-diff"; then
    exact=YES
  else
    exact=NO
    OVERALL=1
  fi
  printf '%s\t%s\t%s\t%s\n' "$model_rel" "$source_count" "$table_count" "$exact" >> "$COMPLETENESS"
done < "$RUN_DIR/raw/table-model-set"

(
  cd "$EXEC_ROOT"
  find . -type f -print0 | sort -z | xargs -0 sha256sum
) > "$RUN_DIR/source-manifest.sha256"

# One Tamarin process per model; every lemma result is still checked exactly once.
while IFS= read -r model_rel; do
  [[ -n "$model_rel" ]] || continue
  model_path="$EXEC_ROOT/$model_rel"
  safe_model="${model_rel//\//__}"
  raw_log="$RUN_DIR/raw/${safe_model}.log"
  command_file="$RUN_DIR/raw/${safe_model}.command"
  model_status_file="$RUN_DIR/raw/${safe_model}.status"
  kind="$(awk -F '\t' -v model="$model_rel" '$1 !~ /^#/ && $2 == model {print $1; exit}' "$EXPECTED_FILE")"
  timeout_seconds="$(awk -F '\t' -v model="$model_rel" '$1 !~ /^#/ && $2 == model {if ($5 > max) max=$5} END {print max+0}' "$EXPECTED_FILE")"

  if [[ ! -f "$model_path" ]]; then
    printf '%s\t%s\t127\t0\tNA\tNA\tNO\tFAIL\n' "$kind" "$model_rel" >> "$MODEL_SUMMARY"
    OVERALL=1
    continue
  fi

  model_sha="$(sha256sum "$model_path" | awk '{print $1}')"
  cmd=(timeout --signal=TERM --kill-after=10 "${timeout_seconds}s"
       "$TAMARIN_PATH" --prove --auto-sources --quit-on-warning
       --derivcheck-timeout=90 -c=30 -s=10 "$model_rel"
       +RTS "-N$RTS_CORES" -RTS)
  public_cmd=("${cmd[@]}")
  public_cmd[4]=tamarin-prover
  printf '%q ' "${public_cmd[@]}" > "$command_file"
  printf '\n' >> "$command_file"
  printf '[%s] ' "$model_rel" >> "$COMMANDS"
  cat "$command_file" >> "$COMMANDS"

  start_ns="$(date +%s%N)"
  (cd "$EXEC_ROOT" && "${cmd[@]}") > "$raw_log" 2>&1
  rc=$?
  end_ns="$(date +%s%N)"
  elapsed_ms=$(( (end_ns - start_ns) / 1000000 ))
  raw_sha="$(sha256sum "$raw_log" | awk '{print $1}')"

  wellformed=NO
  if grep -q 'All wellformedness checks were successful' "$raw_log"; then
    wellformed=YES
  fi
  model_error=NONE
  if [[ "$TOOL_GATE" != PASS ]]; then
    model_error=TOOL_MISMATCH
  elif [[ "$rc" -eq 124 || "$rc" -eq 137 ]]; then
    model_error=TIMEOUT
  elif [[ "$rc" -ne 0 ]]; then
    model_error=ERROR
  elif grep -qi 'WARNING:' "$raw_log"; then
    model_error=WARNING
  elif [[ "$wellformed" != YES ]]; then
    model_error=WELLFORMEDNESS_MISSING
  elif [[ "$(grep -c '^summary of summaries:' "$raw_log" || true)" -ne 1 ]]; then
    model_error=INCOMPLETE
  fi

  model_gate=PASS
  while IFS=$'\t' read -r row_kind row_model lemma expected row_timeout; do
    [[ "$row_kind" != \#* ]] || continue
    [[ "$row_model" == "$model_rel" ]] || continue
    actual=UNKNOWN
    match_count=0
    result_line=''
    if [[ "$model_error" != NONE ]]; then
      actual="$model_error"
    else
      match_count="$(grep -Ec "^  ${lemma} \((exists-trace|all-traces)\): (verified|falsified)" "$raw_log" || true)"
      if [[ "$match_count" -eq 1 ]]; then
        result_line="$(grep -E "^  ${lemma} \((exists-trace|all-traces)\): (verified|falsified)" "$raw_log")"
        if [[ "$result_line" == *': verified'* ]]; then
          actual=VERIFIED
        elif [[ "$result_line" == *': falsified'* && "$result_line" == *'found trace'* ]]; then
          actual=FALSIFIED
        else
          actual=MALFORMED_RESULT
        fi
      elif [[ "$match_count" -gt 1 ]]; then
        actual=DUPLICATE_RESULT
      fi
    fi

    if [[ "$actual" == "$expected" ]]; then
      gate=PASS
    else
      gate=FAIL
      model_gate=FAIL
      OVERALL=1
    fi

    safe_lemma="${lemma//[^A-Za-z0-9_]/_}"
    {
      printf 'kind=%s\n' "$row_kind"
      printf 'model=%s\n' "$model_rel"
      printf 'lemma=%s\n' "$lemma"
      printf 'expected=%s\n' "$expected"
      printf 'actual=%s\n' "$actual"
      printf 'matching_summary_lines=%s\n' "$match_count"
      printf 'rc=%s\n' "$rc"
      printf 'model_elapsed_ms=%s\n' "$elapsed_ms"
      printf 'model_sha256=%s\n' "$model_sha"
      printf 'raw_log_sha256=%s\n' "$raw_sha"
      printf 'gate=%s\n' "$gate"
    } > "$RUN_DIR/raw/${safe_model}__${safe_lemma}.status"

    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$row_kind" "$model_rel" "$lemma" "$expected" "$actual" "$rc" \
      "$elapsed_ms" "$model_sha" "raw/${safe_model}.log" "$gate" >> "$SUMMARY"
    printf '%-9s %-10s %s :: %s\n' "$gate" "$actual" "$model_rel" "$lemma"
  done < "$EXPECTED_FILE"

  if [[ "$model_error" != NONE ]]; then
    model_gate=FAIL
    OVERALL=1
  fi
  {
    printf 'kind=%s\n' "$kind"
    printf 'model=%s\n' "$model_rel"
    printf 'rc=%s\n' "$rc"
    printf 'elapsed_ms=%s\n' "$elapsed_ms"
    printf 'model_sha256=%s\n' "$model_sha"
    printf 'raw_log_sha256=%s\n' "$raw_sha"
    printf 'wellformed=%s\n' "$wellformed"
    printf 'model_error=%s\n' "$model_error"
    printf 'gate=%s\n' "$model_gate"
  } > "$model_status_file"
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$kind" "$model_rel" "$rc" "$elapsed_ms" "$model_sha" "$raw_sha" \
    "$wellformed" "$model_gate" >> "$MODEL_SUMMARY"
done < "$RUN_DIR/raw/table-model-set"

# Secret scan: no private-key blocks or credential-like assignments may enter evidence.
pem_prefix='-----BEGIN '
pem_word='PRIVATE'
pem_suffix=' KEY-----'
assign_password='pass(word|wd)?'
assign_api='api[_-]?key'
assign_token='access[_-]?token'
secret_regex="${pem_prefix}[A-Z0-9 ]*${pem_word}${pem_suffix}|(^|[^A-Za-z0-9_])(${assign_password}|${assign_api}|${assign_token})[[:space:]]*[:=]"
grep -RInE --exclude='secret-scan.txt' -- "$secret_regex" "$RUN_DIR" > "$RUN_DIR/secret-scan.txt"
SECRET_SCAN_RC=$?
if [[ "$SECRET_SCAN_RC" -eq 0 ]]; then
  SECRET_GATE=FAIL_MATCH
  OVERALL=1
elif [[ "$SECRET_SCAN_RC" -eq 1 ]]; then
  SECRET_GATE=PASS
  printf 'secret_scan=PASS; no configured credential/private-key patterns found\n' > "$RUN_DIR/secret-scan.txt"
else
  SECRET_GATE=FAIL_ERROR
  OVERALL=1
  printf 'secret_scan=FAIL_ERROR; grep_rc=%s\n' "$SECRET_SCAN_RC" > "$RUN_DIR/secret-scan.txt"
fi

FINISHED_UTC="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
printf 'finished_utc=%s\n' "$FINISHED_UTC" >> "$VERSIONS"
printf 'secret_gate=%s\n' "$SECRET_GATE" >> "$VERSIONS"

if [[ "$OVERALL" -eq 0 ]]; then
  FINAL_STATUS=VERIFIED_EXPECTATIONS_MET
else
  FINAL_STATUS=FAILED_CLOSED
fi
printf '%s\n' "$FINAL_STATUS" > "$RUN_DIR/overall.status"

{
  printf 'seal_schema=tamarin-evidence-v1\n'
  printf 'run_id=%s\n' "$RUN_ID"
  printf 'finished_utc=%s\n' "$FINISHED_UTC"
  printf 'final_status=%s\n' "$FINAL_STATUS"
  printf 'tool_gate=%s\n' "$TOOL_GATE"
  printf 'secret_gate=%s\n' "$SECRET_GATE"
  printf 'positive_expected=%s\n' "$(awk -F '\t' '$1 == "positive" {n++} END {print n+0}' "$EXPECTED_FILE")"
  printf 'negative_expected=%s\n' "$(awk -F '\t' '$1 == "negative-mutant" {n++} END {print n+0}' "$EXPECTED_FILE")"
  printf 'failed_lemma_gates=%s\n' "$(awk -F '\t' 'NR > 1 && $10 != "PASS" {n++} END {print n+0}' "$SUMMARY")"
} > "$RUN_DIR/seal-metadata.txt"

(
  cd "$RUN_DIR"
  find . -type f ! -name 'evidence-manifest.sha256' ! -name 'evidence-seal.sha256' \
    -print0 | sort -z | xargs -0 sha256sum
) > "$RUN_DIR/evidence-manifest.sha256"
(
  cd "$RUN_DIR"
  sha256sum evidence-manifest.sha256 seal-metadata.txt
) > "$RUN_DIR/evidence-seal.sha256"

if [[ "$OVERALL" -eq 0 ]]; then
  printf 'All positive lemmas verified and all negative-mutant expectations matched.\n'
  printf 'Evidence sealed at: %s\n' "$RUN_DIR"
  exit 0
fi

printf 'At least one fail-closed gate failed; sealed evidence: %s\n' "$RUN_DIR" >&2
exit 1
