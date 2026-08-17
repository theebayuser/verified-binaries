# verified-binaries

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

Requires Rust 1.95.0 with the `wasm32-unknown-unknown` target, `wasm-tools`
(1.252.0 was used), and the Lean toolchain in `lean/lean-toolchain`.

```bash
just prove          # check the proofs
just check          # full pipeline: rust -> wasm -> Lean -> proofs
just verify-hashes  # confirm the committed artifacts are the ones proved about
```

`just emit` regenerates the `Program.lean` modules and additionally needs a
`verifier` binary built from the pinned Talos checkout; point `VERIFIER` at it.
Every generated module embeds the exact WAT text it was decoded from and fails
to build if the staged file differs by a byte, so a generated module cannot
drift away from the binary it describes.

## What a certificate here does and does not cover

Proved: the stated properties of the decoded wasm module, against the Talos
semantics, checked by the Lean kernel.

Not proved, and deliberately part of the trust base: that rustc compiled the
source faithfully (the proofs are about its output, so a miscompilation shows up
as a wrong theorem statement only if the model is also wrong), that
`wasm-tools print` and the Talos decoder agree with the wasm binary format, and
that any particular embedder implements the semantics the model describes.

## Current state

- Pure model and its correctness lemmas: proved, no `sorry`, and dependency-free
  so the specification can be reviewed on its own.
- Both artifacts compiled, staged, decoded into Lean, and hash-recorded.
- Recon of the emitted code written up in `docs/wat-recon.md`.
- Wasm-level proofs: in progress.

## License

AGPL-3.0, matching Talos, whose CodeLib and interpreter this depends on.
Talos is © Cajal Technologies and is used here as a Lake git dependency.
