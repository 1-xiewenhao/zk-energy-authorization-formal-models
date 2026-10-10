# Reference verification results

Both suites were rerun from the standalone public package on 10 October 2026
on a multi-core Linux instance. The 15 input models retain their original
bytes, checked against the study's existing model sources and the released
model checksum list. Only publication documentation, runner portability,
output paths and tool-metadata handling were adapted for this release.

The reference archives contain only these two successful fresh runs. Historical
records and incomplete checks on other instances are not used as the
reference evidence. No raw proof output in these accepted runs was edited
after generation. Relative model paths were used during execution.

| Suite | Fresh reference run | Outcome |
|---|---|---|
| ProVerif 2.05 | `proverif-20261010T083615Z` | PASS; 27 security/secrecy queries TRUE, two honest-reachability traces, and four named negative controls falsified |
| Tamarin 1.12.0 / Maude 3.5.1 | `20261010T083615Z` | VERIFIED_EXPECTATIONS_MET; 34 positive lemmas VERIFIED; both negative controls executable and their named security lemmas FALSIFIED |

All 41 ProVerif expected query results and all 38 Tamarin lemma results match
their complete expectation tables. Tamarin's positive count includes five
executability lemmas. Supporting ProVerif mutant controls are checked but are
not counted as additional positive security claims.

## Complete records

`evidence/proverif-reference.zip` and `evidence/tamarin-reference.zip` contain
complete raw outputs, model-relative commands, tool versions and executable
hashes, statuses, source snapshots, and integrity manifests. The runners use
the same documented proof-search parameters and four Tamarin RTS cores. The
ProVerif source-archive checksum is checked and recorded. Tool binaries and
private prototype sources are not distributed.

Check and unpack the archives from the repository root:

```bash
(cd evidence && sha256sum -c SHA256SUMS.txt)
unzip evidence/proverif-reference.zip -d reference-runs
unzip evidence/tamarin-reference.zip -d reference-runs
(cd reference-runs/proverif-20261010T083615Z && sha256sum -c manifest.sha256)
(cd reference-runs/20261010T083615Z && sha256sum -c evidence-manifest.sha256)
```

ProVerif's `summary.json`/`summary.tsv` and Tamarin's
`lemma-status.tsv`/`model-status.tsv` provide the complete status mapping.
The source snapshots inside each archive are the inputs belonging to that
run. The actual executable hashes identify the reference builds; independent
builds of the same pinned versions may have different executable hashes.

## Interpretation

TRUE/VERIFIED results hold within the corresponding symbolic models and their
stated assumptions. ProVerif FALSE for a negated honest-event query is an
expected reachability witness. FALSE/FALSIFIED for a deliberately weakened
negative control is the required sensitivity result. Neither is a
counterexample to a positive security model.

Timeouts, unknown results, missing/duplicate expected results, tool errors, or
mismatched outcomes do not count as successful verification. These records
are not performance measurements and do not prove physical sensor accuracy
or complete implementation correctness. See `model-specification.md` for
the precise claim boundaries.
