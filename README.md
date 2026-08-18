# verified-binaries

[![CI](https://github.com/theebayuser/verified-binaries/actions/workflows/ci.yml/badge.svg)](https://github.com/theebayuser/verified-binaries/actions/workflows/ci.yml)

Machine-checked correctness certificates for compiled WebAssembly binaries.

This repository takes a real Rust function, compiles it to wasm with an
unmodified toolchain, and proves things about **the artifact that comes out of
the compiler** rather than about the source. The proofs are in Lean 4 and run
against the [Talos](https://github.com/cajal-technologies/talos) small-step Wasm
semantics and its Iris separation logic, consumed as an ordinary dependency at a
pinned commit. No Talos source is vendored here.

Status: work in progress. What is proved so far is listed under
[Current state](#current-state); nothing below is claimed until it is in the
build.

## The claim being built

`binary_search` is compiled twice from byte-identical Rust source, at
`opt-level = 0` and `opt-level = 3`, and the two artifacts get:

1. **Total functional correctness of the optimized artifact.** For a sorted
   `u32` array in linear memory, the compiled export terminates and returns an
   index holding the target when the target is present, and `-1` when it is
   absent. Termination is proved from a well-founded measure, not assumed.
   This one is done; see [Current state](#current-state).
2. **Observational equivalence of the two artifacts.** The unoptimized and
   optimized builds agree on the observable outcome for every input meeting the
   precondition.

The optimized build is the interesting one. `opt-level = 3` inlines the slice
construction and the inner call, drops the shadow stack, keeps the loop state in
registers, and turns the division by two into a shift. Nothing about it looks
like the Rust it came from, which is exactly why proving it directly is worth
doing.

## Layout

```
rust/                        cargo workspace
  binary_search/             opt-level 0 crate
  binary_search_opt3/        opt-level 3 crate, byte-identical source
  build/<crate>/             staged program.wasm + program.wat (committed)
lean/Project/
  BinarySearch/Pure.lean     the model and its lemmas, dependency-free
  BinarySearch/Program.lean  auto-generated from the wasm
  BinarySearchOpt3/          same, for the optimized artifact
docs/wat-recon.md            what the compiler actually emitted, and why the
                             proof is shaped the way it is
docs/artifacts.sha256        hashes for every artifact in the chain
```

The two crates share their source exactly; `docs/artifacts.sha256` shows the
identical source hashes and the differing wasm hashes.

## Building

Checking the proofs needs [`elan`](https://github.com/leanprover/elan) (it
installs the toolchain pinned in `lean/lean-toolchain`) and
[`just`](https://github.com/casey/just). Fetch the Mathlib build cache first,
or the first build compiles Mathlib from source:

```bash
cd lean && lake exe cache get && cd ..
just prove          # check the proofs; warnings are errors
just verify-hashes  # confirm the committed artifacts are the ones proved about
just axioms         # which theorems depend on which axioms
```

Rebuilding the wasm is optional and separate. `just build-wasm`, `just emit`
and `just check` additionally need Rust 1.95.0 with the
`wasm32-unknown-unknown` target, `wasm-tools` (1.252.0 was used), and a
`verifier` binary built from the pinned Talos checkout with `VERIFIER` pointed
at it. The staged wasm is committed and hash-pinned, so none of that is
required to check what is proved. Every generated module embeds the exact WAT
text it was decoded from and fails to build if the staged file differs by a
byte, so a generated module cannot drift away from the binary it describes.

## What a certificate here does and does not cover

Proved: the stated properties of the decoded wasm module, against the Talos
semantics, checked by the Lean kernel.

Not proved, and deliberately part of the trust base:

- **The Talos semantics.** Everything here is proved against Talos's small-step
  model of Wasm. If that model diverges from the specification, the theorems
  hold of the model and say nothing about a real engine. Same for any embedder:
  a certificate binds an implementation only to the extent the implementation
  matches the semantics.
- **The decoder and `wasm-tools print`.** The theorems are about the module
  Talos decoded from the committed bytes. Hash-pinning ties that back to the
  exact bytes, but not to the wasm binary format itself.
- **What the Rust source means.** The proofs are about the compiler's output,
  so a rustc miscompilation would not make any theorem here false; it would
  make the proved artifact compute something other than what the Rust says. The
  connection to the source's intent runs through `Pure.lean`, which is
  hand-written and read, not derived from the Rust.
- **`native_decide` for the concrete per-input results.** Those theorems trust
  the compiled evaluator rather than the kernel alone. They are quarantined in
  `Smoke.lean` / `Equivalence.lean`, and no universal statement depends on
  them; `just axioms` and CI both enforce that boundary.

## Current state

Proved, `lake build --wfail` clean, no `sorry`:

- **Symbolic total correctness of the optimized artifact.** For every `u32`
  array laid out anywhere in the heap region and every target, the decoded
  `opt-level = 3` export terminates and returns exactly what the pure model
  returns (`BinarySearchOpt3Spec` in `BinarySearchOpt3/Spec.lean`, proved by
  `binarySearchOpt3Spec_holds` in `BinarySearchOpt3/TotalProof.lean`).
  Termination comes from a well-founded measure on the loop, the compiler's
  bounds-check branch is discharged as unreachable from the loop invariant,
  and the statement is fuel-free. `terminates_hit` and `terminates_miss`
  interpret the returned value: a non-sentinel answer is an index holding the
  target with no sortedness assumption at all, and for sorted input the
  sentinel means the target is absent. The whole chain depends on Lean's
  standard axioms only; `just axioms` shows it, and CI fails if that changes.
- **The model and its correctness lemmas.** A reported hit is genuine
  (`searchResult_hit`), and the sentinel is returned only when the target really
  is absent (`searchResult_miss`, which is where sortedness is needed). This
  file imports nothing, so the specification can be checked against a bare Lean
  toolchain without building the verification stack.
- **Both compiled artifacts agree with the model on concrete inputs**, by
  running the decoded binaries: hits at the first, middle and last positions,
  misses below, between and above, the empty array, and duplicates. Nine cases
  for the optimized build, three for the unoptimized one.
- **The two artifacts are observationally equivalent on three of those inputs**
  (`ObservationallyEquivOn`): a hit in the middle, a miss between two elements,
  and the empty array, where the optimized build tests the length up front and
  never enters its loop.
- **The total-WP rules the symbolic proof needs** for `i32.shr_u`, `i32.gt_u`
  and `i32.ge_u`, which the upstream total lifting library does not carry.

Not yet done: the symbolic proof of the unoptimized artifact and the symbolic
form of the equivalence statement. Both are parked on the same missing piece:
the unoptimized build spills its loop state through `global.get` / `global.set`
(the shadow stack), and the upstream total lifting library has no rules for
those yet. The concrete per-input results depend
on `native_decide` and are quarantined in `Smoke.lean` / `Equivalence.lean`;
`just axioms` prints exactly which theorems those are. Every universal
statement, including the symbolic proof above, carries the standard axioms
only.

## License

AGPL-3.0, matching Talos, whose CodeLib and interpreter this depends on.
Talos is © Cajal Technologies and is used here as a Lake git dependency.
