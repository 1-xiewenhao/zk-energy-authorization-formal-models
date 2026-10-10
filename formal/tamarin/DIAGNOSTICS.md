# Evidence inclusion policy

Only the five positive models and two deliberate negative controls named in
`expected.tsv` contribute to this release. The complete source lemma set must
match the table before an acceptance run can pass.

Timeouts and incomplete proof searches are not verification. Deliberate
negative controls are labeled as such and their counterexamples must not be
reported as attacks on the positive models. Source snapshots, raw outputs,
and source/evidence hashes are preserved within each new run.
