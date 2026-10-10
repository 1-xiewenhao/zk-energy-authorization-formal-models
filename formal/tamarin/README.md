# Tamarin models

Run `bash formal/tamarin/run_all.sh` from the repository root. Set
`TAMARIN_BIN` and `MAUDE_BIN` when the pinned tools are not on PATH.

The authoritative expected lemma list is `expected.tsv`. The runner checks
that source lemma names match the table, checks each result exactly once,
requires successful well-formedness and no warnings, and treats timeouts or
unexpected outcomes as failures. All positive models and both negative
controls are run by the same script.

| Model | Role |
|---|---|
| `models/auth-binding.spthy` | Credential-secret possession, device/payer control, exact policy and derived event identity |
| `models/freshness-replay.spthy` | Conditional validity guards, monotonic counter transitions, and single-use state |
| `models/relay-quorum.spthy` | Distinct 2-of-3 observers, certificate origin, and corruption-qualified finality correspondence |
| `models/settlement-binding.spthy` | Exact prepared-order/payment correspondence and event/context at-most-once settlement |
| `models/protocol-v2-e2e.spthy` | Executable finite interface composition and authorization-to-settlement correspondences |

The positive set has 34 lemmas, including five executability checks. The
counter-state deletion mutant must falsify
`credential_counter_value_single_use`; the order-recomputation deletion mutant
must falsify `exact_payment_context_binding`. Both mutants must retain an
executable trace. See the source comments and
`../../docs/model-specification.md` for their abstraction boundaries.

Proof commands retain `--prove --auto-sources --quit-on-warning
--derivcheck-timeout=90 -c=30 -s=10` and four RTS cores by default. A UTF-8
locale is required. Model-specific timeouts are recorded in `expected.tsv`.
