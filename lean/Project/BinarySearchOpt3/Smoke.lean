import Project.BinarySearchOpt3.Program
import Project.BinarySearch.Pure

/-!
# Concrete regression certificates for the optimized artifact

Each theorem runs the decoded binary on a fixed input and checks that the
returned value is exactly what the pure model predicts, so a wrong entry
configuration or a drifted model shows up immediately rather than at the end of
the symbolic proof.

These are regressions, not the specification. Each is about a single input and
each leans on `native_decide`, so nothing universal is allowed to rest on them;
the symbolic statement lives in `Spec.lean` and does not depend on this file.
-/

namespace Project.BinarySearchOpt3.Smoke

open Wasm
open Project.BinarySearch.Pure

/-- Place `u32` values at consecutive addresses starting at `base`. -/
private def writeWords (m : Mem) (base : UInt32) : List UInt32 → Mem
  | [] => m
  | v :: vs => writeWords (m.write32 base v) (base + 4) vs

/-- `__heap_base` for this module: above every data segment the compiler
emitted, so the array cannot overlap the panic strings. -/
def heapBase : UInt32 := 1049808

/-- Entry configuration for the export, with `arr` laid out at `heapBase`. -/
def config (arr : List UInt32) (target : UInt32) : Wasm.SmallStep.Config Unit :=
  let initial : Store Unit := «module».initialStore
  { expr := .running
      ⟨⟨[.i32 heapBase, .i32 (UInt32.ofNat arr.length), .i32 target],
          [.i32 0, .i32 0, .i32 0, .i32 0], []⟩,
        func0, 1, [], [], []⟩
    store :=
      { runtime := { module := «module», host := {} }
        wasm := { initial with mem := writeWords initial.mem heapBase arr } } }

/-- The binary returns exactly what the model predicts, on this input. -/
private abbrev AgreesOn (arr : List UInt32) (target : UInt32) : Prop :=
  Wasm.SmallStep.TerminatesWith (config arr target)
    (fun values _ => values = [.i32 (searchResult arr target)])

private def sample : List UInt32 := [10, 20, 30, 40, 50]
private def dups : List UInt32 := [7, 7, 7, 9, 9]

theorem agrees_hit_middle : AgreesOn sample 30 := by
  apply Wasm.SmallStep.runSteps_checked_terminates (fuel := 500)
    (fun values _ => decide (values = [.i32 (searchResult sample 30)]))
  · native_decide
  · intro values store h; exact of_decide_eq_true h

theorem agrees_hit_first : AgreesOn sample 10 := by
  apply Wasm.SmallStep.runSteps_checked_terminates (fuel := 500)
    (fun values _ => decide (values = [.i32 (searchResult sample 10)]))
  · native_decide
  · intro values store h; exact of_decide_eq_true h

theorem agrees_hit_last : AgreesOn sample 50 := by
  apply Wasm.SmallStep.runSteps_checked_terminates (fuel := 500)
    (fun values _ => decide (values = [.i32 (searchResult sample 50)]))
  · native_decide
  · intro values store h; exact of_decide_eq_true h

theorem agrees_miss_between : AgreesOn sample 35 := by
  apply Wasm.SmallStep.runSteps_checked_terminates (fuel := 500)
    (fun values _ => decide (values = [.i32 (searchResult sample 35)]))
  · native_decide
  · intro values store h; exact of_decide_eq_true h

theorem agrees_miss_below : AgreesOn sample 1 := by
  apply Wasm.SmallStep.runSteps_checked_terminates (fuel := 500)
    (fun values _ => decide (values = [.i32 (searchResult sample 1)]))
  · native_decide
  · intro values store h; exact of_decide_eq_true h

theorem agrees_miss_above : AgreesOn sample 99 := by
  apply Wasm.SmallStep.runSteps_checked_terminates (fuel := 500)
    (fun values _ => decide (values = [.i32 (searchResult sample 99)]))
  · native_decide
  · intro values store h; exact of_decide_eq_true h

/-- The empty array: the loop is never entered. -/
theorem agrees_empty : AgreesOn [] 3 := by
  apply Wasm.SmallStep.runSteps_checked_terminates (fuel := 500)
    (fun values _ => decide (values = [.i32 (searchResult [] 3)]))
  · native_decide
  · intro values store h; exact of_decide_eq_true h

/-- Duplicates: the model must predict the same occurrence the binary lands
on, which is not necessarily the leftmost. -/
theorem agrees_duplicates : AgreesOn dups 7 := by
  apply Wasm.SmallStep.runSteps_checked_terminates (fuel := 500)
    (fun values _ => decide (values = [.i32 (searchResult dups 7)]))
  · native_decide
  · intro values store h; exact of_decide_eq_true h

theorem agrees_duplicates_upper : AgreesOn dups 9 := by
  apply Wasm.SmallStep.runSteps_checked_terminates (fuel := 500)
    (fun values _ => decide (values = [.i32 (searchResult dups 9)]))
  · native_decide
  · intro values store h; exact of_decide_eq_true h

end Project.BinarySearchOpt3.Smoke
