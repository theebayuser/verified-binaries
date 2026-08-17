import CodeLib

/-!
# Total-WP rules for the instructions this corpus needs

Total counterparts of the partial `wp_` rules for `i32.shr_u`, `i32.gt_u` and
`i32.ge_u`. The generic total lifting library in `CodeLib.SepLogic`
(`SmallStepTotalLifting.lean`) covers arithmetic, comparison against `<u`,
control flow, locals and 32-bit memory, but not these three, which the
compiled binary search uses: `shr_u` for the halving, `ge_u` for the bounds
check the optimizer emits, and `gt_u` for the third branch of the comparison.

Each is a pure step, so each is a direct application of `twp_pureStep` against
the corresponding `Step` constructor, following the pattern the upstream
selection-sort example uses for its own local i64 rules.
-/

namespace Wasm.SmallStep

open Iris Iris.ProgramLogic Language.Notation Std
open Wasm.SepLogic

variable [WasmSmallStepGS hlc α]
local instance instBinarySearchWasmTotalIrisGS :
    IrisGS_gen hlc (Expr α) (WasmHeapGF α) :=
  instIrisGS
variable {s : Stuckness} {E : CoPset}
variable {Φ : List Value → IProp (WasmHeapGF α)}

/-- `i32.shr_u`: logical right shift, with the shift amount taken mod 32. -/
theorem twp_shrU
    {params localValues values : List Value}
    {lhs rhs : UInt32} {code : Program} {arity : Nat}
    {remainder : List Value} {controls : List ControlFrame}
    {calls : List CallFrame} :
    WP (.running
      ⟨⟨params, localValues, .i32 (lhs >>> (rhs % 32)) :: values⟩,
        code, arity, remainder, controls, calls⟩ : Expr α) @ s; E [{ Φ }] ⊢
    WP (.running
      ⟨⟨params, localValues, .i32 rhs :: .i32 lhs :: values⟩,
        .shrU :: code, arity, remainder, controls, calls⟩ : Expr α) @ s; E
      [{ Φ }] :=
  twp_pureStep _ _ _ (fun _ => Step.shrU)

/-- `i32.gt_u`: unsigned greater-than, pushing 1 or 0. -/
theorem twp_gtU
    {params localValues values : List Value}
    {lhs rhs : UInt32} {result : UInt32} {code : Program} {arity : Nat}
    {remainder : List Value} {controls : List ControlFrame}
    {calls : List CallFrame}
    (hresult : result = if lhs > rhs then 1 else 0) :
    WP (.running
      ⟨⟨params, localValues, .i32 result :: values⟩,
        code, arity, remainder, controls, calls⟩ : Expr α) @ s; E [{ Φ }] ⊢
    WP (.running
      ⟨⟨params, localValues, .i32 rhs :: .i32 lhs :: values⟩,
        .gtU :: code, arity, remainder, controls, calls⟩ : Expr α) @ s; E
      [{ Φ }] :=
  twp_pureStep _ _ _ (fun _ => Step.gtU hresult)

/-- `i32.ge_u`: unsigned greater-or-equal, pushing 1 or 0. -/
theorem twp_geU
    {params localValues values : List Value}
    {lhs rhs : UInt32} {result : UInt32} {code : Program} {arity : Nat}
    {remainder : List Value} {controls : List ControlFrame}
    {calls : List CallFrame}
    (hresult : result = if lhs ≥ rhs then 1 else 0) :
    WP (.running
      ⟨⟨params, localValues, .i32 result :: values⟩,
        code, arity, remainder, controls, calls⟩ : Expr α) @ s; E [{ Φ }] ⊢
    WP (.running
      ⟨⟨params, localValues, .i32 rhs :: .i32 lhs :: values⟩,
        .geU :: code, arity, remainder, controls, calls⟩ : Expr α) @ s; E
      [{ Φ }] :=
  twp_pureStep _ _ _ (fun _ => Step.geU hresult)

end Wasm.SmallStep
