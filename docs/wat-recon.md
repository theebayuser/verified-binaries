# WAT recon: `binary_search` at opt-level 0 and 3

Recorded 2026-08-17 against rustc 1.95.0 (`wasm32-unknown-unknown`),
wasm-tools 1.252.0. Both artifacts come from byte-identical Rust source; the
only difference is the `opt-level` set per package in `rust/Cargo.toml`.

Purpose: fix the proof shape before writing any Lean. Everything below is read
off the emitted WAT, not assumed.

## Export surface (identical in both)

```
(export "memory" (memory 0))
(export "binary_search" (func $binary_search))
(export "__data_end" (global 1))
(export "__heap_base" (global 2))
```

Signature `(param i32 i32 i32) (result i32)` = `(ptr, len, target) -> index`,
with `-1` for absent. 60 functions total at opt0, 58 at opt3; all but the
exported one (and the panic path it calls) are unreachable Rust-std machinery.

## opt-level 3: locals only, no shadow stack

The exported function *is* the whole algorithm: `from_raw_parts` and the inner
`binary_search` are both inlined away.

State lives in locals: `3` = lo, `4` = hi, `5` = mid, `6` = loaded element.
Shape: `len == 0` is tested up front (`i32.eqz`), then a bottom-tested loop
(`do { ... } while (lo < hi)`). Midpoint is `((hi - lo) >>u 1) + lo`. The
bounds check is `mid >=u len -> panic`, which the proof discharges as
unreachable from the invariant `lo <= mid < hi <= len`.

Instruction multiset of the exported function:

| count | instruction | count | instruction |
|---|---|---|---|
| 18 | `local.get` | 1 | `i32.sub` |
| 6 | `i32.const` | 1 | `i32.shr_u` |
| 5 | `local.set` | 1 | `i32.shl` |
| 5 | `br_if` | 1 | `i32.load` |
| 5 | `block` | 1 | `i32.gt_u` |
| 3 | `i32.add` | 1 | `i32.ge_u` |
| 2 | `local.tee` | 1 | `i32.eqz` |
| 2 | `i32.lt_u` | 1 | `loop` / `br` / `return` |
| | | 1 | `call` + `unreachable` (panic path only) |

**No `global.get` / `global.set`, no `i32.store`, no `i32.div_u`.** Division by
two is compiled to `i32.shr_u`.

## opt-level 0: shadow-stack frame, spilled loop state

Two functions are involved. The exported `$binary_search` shim subtracts 16
from `$__stack_pointer`, calls `core::slice::raw::from_raw_parts` to
materialize the slice into the frame, reloads `ptr`/`len` from `offset=8` /
`offset=12`, and calls the inner `binary_search`. The inner function takes its
own 16-byte frame and keeps loop state in memory rather than locals:

- `offset=4` result slot, `offset=8` = lo, `offset=12` = hi.

Its multiset adds `i32.store` (6), `i32.and` (5, the `br_if` boolean
normalization), `global.get`/`global.set`, and a second `call` +
`unreachable` panic path.

## Rule coverage needed

Available in talos main `3d742fb` (the pin as of 2026-08-25;
`codelib/CodeLib/SepLogic/SmallStepTotalLifting.lean`): `twp_pureStep`,
`twp_finish`, `twp_returnFromFunction`, `twp_const`, `twp_add`, `twp_sub`,
`twp_mul`, `twp_shl`, `twp_remU`, `twp_eqz`, `twp_ltU`, `twp_iff`,
`twp_block`, `twp_loop`, `twp_exitControl`, `twp_br`, `twp_brIf`,
`twp_brIfZero`, `twp_localGet`, `twp_localSet`, `twp_localTee`, `twp_call`,
`twp_returnFromCallExplicit`, `twp_load32`, `twp_store32`, `twp_and`,
`twp_globalGet`, `twp_globalSet` (both stated for global index 0, which is
this module's `$__stack_pointer`); plus `twp_loop_wf_family` in
`SmallStepTotalLoop.lean`.

Still local to this repo (`Project/BinarySearch/Rules.lean`; all
`twp_pureStep` one-liners over existing `Step` constructors):

| rule | needed by |
|---|---|
| `twp_shrU` | both |
| `twp_geU` | opt3 bounds check |
| `twp_gtU` | both |

`local.tee` needs no rule: the WAT decoder desugars it to `local.set` +
`local.get`.

## Consequence for proof order

opt3 was proved first: it needs only rules we can write ourselves, has no
shadow stack, and is a single self-contained function. opt0 additionally
needs total rules for `global.get`/`global.set`, which landed in talos main
with the M8 total-correctness merge (2026-08-20), so nothing blocks it at the
rule level any more.

This also states the result more strongly: the artifact that would actually
ship is the optimized one, and it is the one whose correspondence to the
source is least obvious by inspection.
