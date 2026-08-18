# verified-binaries
#
# `VERIFIER` must point at a `verifier` binary built from the pinned Talos
# checkout (see README). `build-wasm`, `emit` and `check` need it; `prove`,
# `axioms`, `diff-sources`, `hashes` and `verify-hashes` do not.

VERIFIER := env_var_or_default("VERIFIER", "verifier")

default:
    @just --list

# Compile both crates to wasm and stage build/<crate>/program.{wasm,wat}.
build-wasm:
    {{VERIFIER}} build

# Regenerate the Program.lean modules from the staged wasm.
emit:
    {{VERIFIER}} emit --force-emit

# Check the proofs. This is the gate: warnings are errors.
prove:
    cd lean && lake build --wfail

# Full pipeline: rust -> wasm -> Lean -> proofs.
check:
    {{VERIFIER}} check

# Which theorems depend on which axioms, and in particular which ones use
# native_decide. See docs/axiom-audit.lean for what to expect.
axioms:
    cd lean && lake env lean ../docs/axiom-audit.lean

# The two crates must stay byte-identical; only the opt-level differs.
diff-sources:
    diff rust/binary_search/src/lib.rs rust/binary_search_opt3/src/lib.rs
    diff rust/binary_search/src/exports.rs rust/binary_search_opt3/src/exports.rs
    @echo "sources identical"

# Record hashes of every artifact between the Rust source and the proofs.
hashes:
    #!/usr/bin/env bash
    set -euo pipefail
    : > docs/artifacts.sha256
    for c in binary_search binary_search_opt3; do
      shasum -a 256 "rust/$c/src/lib.rs" "rust/$c/src/exports.rs" \
        "rust/build/$c/program.wasm" "rust/build/$c/program.wat" >> docs/artifacts.sha256
    done
    shasum -a 256 lean/Project/BinarySearch/Program.lean \
      lean/Project/BinarySearchOpt3/Program.lean >> docs/artifacts.sha256
    cat docs/artifacts.sha256

# Verify the committed artifacts still match their recorded hashes.
verify-hashes:
    shasum -a 256 --check docs/artifacts.sha256
