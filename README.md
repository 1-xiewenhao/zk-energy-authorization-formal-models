# ZK-assisted energy authorization: formal verification artifacts

This repository provides the complete symbolic verification artifacts for
**Privacy-Preserving Energy Service Authorization for Mobile Industrial IoT
Agents: A ZK-Assisted Dual-Ledger Framework**.

The release contains executable ProVerif and Tamarin models, all queried
properties, deliberately weakened negative controls, verification runners,
modeling assumptions, and reference verification outputs. It covers the formal
analysis component of the study. The full prototype, smart-contract sources,
circuits, deployment configurations, and experimental datasets are outside
this release.

## Contents

| Directory | Contents |
|---|---|
| `formal/proverif/` | Four main/check models and four negative controls; exact expected query selectors and runner |
| `formal/tamarin/` | Five positive stateful models and two negative controls; complete lemma table and runner |
| `docs/` | Protocol-to-model mapping, assumptions, toolchain instructions, and result interpretation |
| `evidence/` | Complete fresh reference-run archives, summary, and archive checksums |

## Reproduce the verification

Use Linux, or Ubuntu in WSL2. Requirements: Bash, GNU coreutils (`timeout`,
`sha256sum`), Node.js **20.x**, ProVerif **2.05**, Tamarin Prover **1.12.0**, and Maude
**3.5.1**. See [toolchain instructions](docs/toolchain.md).

From the repository root:

```bash
# Builds ProVerif from its checksum-verified official source archive.
bash formal/proverif/build-proverif-2.05.sh
bash formal/proverif/run-proverif.sh

# Make tamarin-prover and maude available on PATH before running this command.
bash formal/tamarin/run_all.sh
```

Alternatively, select existing installations explicitly:

```bash
PROVERIF_BIN=/path/to/proverif bash formal/proverif/run-proverif.sh
TAMARIN_BIN=/path/to/tamarin-prover MAUDE_BIN=/path/to/maude \
  bash formal/tamarin/run_all.sh
```

The runners pin tool versions and record the actual executable hashes. A
locally compiled executable may have a different hash from the reference
binary. Tool versions, model hashes, commands, and property outcomes are
recorded separately; identical binary hashes across platforms are not assumed.

## Expected results

* ProVerif: **27 security/secrecy queries TRUE**, plus **two honest-reachability
  checks FALSE with traces**. Four negative controls must falsify their named
  security queries and produce traces. Additional mutant control queries must
  match `expected-results.json`.
* Tamarin: **34 positive lemmas VERIFIED**, including five executability
  lemmas. Each of the two negative controls has an executable trace and a
  named security lemma that must be FALSIFIED.

An expected counterexample in a deliberately weakened model is a successful
negative-control check. It is not a counterexample to the corresponding
positive model. Timeouts, unknown or missing results, unexpected outcomes,
and tool errors fail the run; Tamarin warnings also fail the run.

ProVerif correspondence/secrecy analysis and Tamarin stateful analysis are
complementary. The claims depend on the assumptions in
[the model specification](docs/model-specification.md). In particular, these
models do not establish physical sensor truth, numerical clock arithmetic,
Groth16 cryptographic soundness itself, adaptive-query privacy, unconditional
availability, atomic cross-ledger settlement, or complete implementation
correctness.

## Integrity

`MODEL-SHA256SUMS.txt` identifies the published model bytes. Each reference
run also includes its own source and evidence manifests. From the repository
root, check the released models with:

```bash
sha256sum -c MODEL-SHA256SUMS.txt
```

Reference-output interpretation is documented in
[verification results](docs/verification-results.md).

## License status

No open-source license is provided with this release.
