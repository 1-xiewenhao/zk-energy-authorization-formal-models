# Protocol-to-model specification and assumptions

## Scope and roles

The models analyze the authorization and settlement message/state interfaces.
Roles are the mobile agent (MEA), credential/policy authority, measurement
attestor, payer, service-ledger authorization process, observer relays, and
payment-ledger settlement process. Public-channel messages are exposed to a
symbolic attacker who can intercept, replay, replace, and construct messages
from known terms. Hashing, signatures, and ideal ZK verification follow the
equations in the model sources.

The ProVerif main models separate authorization, settlement, and explicit
device/payer/attestor compromise. Tamarin separates authorization binding,
freshness/replay state, observer quorum, settlement, and a finite end-to-end
interface composition. These are scoped models, not a single proof of the
entire deployed implementation.

## Registration, account control, and credential possession

A credential associates a device account and payer account with a credential
identifier/version, ZK-key commitment, attestor and energy parameters. A
registered provider policy binds the provider, policy identifier/version,
geometry, energy bounds, payment terms and destination. Successful
authorization must refer to the registered credential and policy represented
in that model.

Device account control and ZK-credential-secret possession are distinct.
Device-origin signatures/transaction authorization establish the former.
The ideal ProVerif equation

```text
verifyZk(zkProof(witness, secret, statement), statement, h(secret)) = ok
```

establishes the symbolic link to the committed credential secret. Tamarin's
`ValidZKProof` capability represents that verification premise. This abstraction
depends on the assumed knowledge soundness of the underlying proof system; it
does not prove Groth16 or its implementation. `zkKeyCommit = h(secret)` is
the registered key commitment. It is distinct from the per-measurement public
circuit output `H_out`.

## Session and authorization context

Issued sessions bind the credential, device/payer accounts, registered policy,
requested energy, freshness information and expiry. The ProVerif
`contextCore` explicitly represents the canonical authorization context.
Tamarin uses scoped context constructors appropriate to each module. Hash
constructors represent unambiguous typed encodings; collision attacks and
byte-level ABI/serialization errors are outside this symbolic analysis.

The authorization-record identity is derived from the source/domain, session,
context hash and nullifier. In Tamarin this is
`eventid(sys, session, ctx, nullifier)`. There is no independent free
authorization identifier. The context itself does not include that derived
event identity, avoiding a circular definition.

## Measurement provenance and conditional freshness

An attestor signature binds the measurement envelope to the authorization
session and relevant context. This establishes origin from the modeled
attestor key, subject to corruption exceptions, rather than the physical
accuracy of location or battery readings. Sensor authenticity and honest
measurement by the attestor remain external assumptions.

`ValidWindow` is an abstract validity guard; numerical timestamp bounds are
not proved. Tamarin's `succ(c)` counter transition represents ordered
per-credential advancement. It supports replay-exclusion/state-transition
claims rather than proofs of machine-integer arithmetic or every possible
numeric jump. Linear session, event, nullifier and counter facts capture
single-use state in the freshness module.

## Payer consent and payment binding

Payer intent binds the system/domain, context, payer, provider, token, amount
and expiry. The intent does not independently sign the derived event identity
or nullifier: those fields are linked through context/event derivation and
separate single-use properties. Provider is also the payee in these models.

Settlement checks the prepared authorization order and exact payment tuple,
including policy/rate/energy fields where represented by the module. The
positive settlement model recomputes/matches context and event/order identity;
the relay cannot replace a payment tuple while preserving an unrelated valid
authorization. Tamarin represents event/context consumption by linear facts.
ProVerif uses a private one-shot process keyed by the exact order, a
message-layer abstraction of at-most-once consumption.

## Observer trust and finality

The modeled certificate quorum consists of two distinct signatures from
three registered observers. It is not an aggregate threshold-signature
cryptosystem. Certificate/finality correspondences are qualified by observer
corruption events: safety relies on fewer than two relevant observer keys
being compromised. The relay module analyzes certificate origin and distinct
quorums; the finite composition module uses those interfaces as scoped
premises. The latter is not a general compositional-security theorem.

## Negative controls and non-vacuity

ProVerif negative controls remove device-origin, exact policy-version,
payer/provider, or exact-order consumption binding. Their named queries must
be FALSE with traces. Tamarin's counter-state mutant removes linear counter
consumption. Its settlement mutant omits exact prepared-order matching and
event/order recomputation, while supplying distinct certificate facts to
isolate the deleted binding. Each Tamarin mutant must retain an executable
trace and falsify its named security lemma.

The main sets also include honest executability/reachability checks. In
ProVerif, a FALSE result for a *negated* honest-event query establishes
reachability. In Tamarin, the corresponding exists-trace lemma must be
VERIFIED. These checks prevent interpreting an unreachable success event as
sufficient security evidence; they do not establish unconditional liveness.

## Claims outside this release

The artifacts do not prove physical sensor truth, numerical clock/range
arithmetic, the underlying cryptographic primitives, privacy against adaptive
accept/reject querying or metadata correlation, progress under arbitrary
network/relay failures, atomic cross-ledger commit/rollback, performance,
or complete Solidity/EVM correctness. The public models make the symbolic
assumptions and property statements independently inspectable. Implementation
and experimental validation are separate evidence in the manuscript.
