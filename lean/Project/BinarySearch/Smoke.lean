import Project.BinarySearch.Program
import Project.BinarySearch.Pure

/-!
# Concrete regression certificates for the unoptimized artifact

The same regressions as for the optimized build, against the `opt-level = 0`
artifact. This one is a two-function affair: the export is `func2`, a shim that
takes a shadow-stack frame, materializes the slice, and calls the inner
`func0`, which keeps its loop state spilled in its own frame.

As with the optimized build these are concrete regressions leaning on
`native_decide`, kept out of the symbolic development.
-/

namespace Project.BinarySearch.Smoke

open Wasm
open Project.BinarySearch.Pure

/-- Place `u32` values at consecutive addresses starting at `base`. -/
private def writeWords (m : Mem) (base : UInt32) : List UInt32 → Mem
  | [] => m
  | v :: vs => writeWords (m.write32 base v) (base + 4) vs

/-- `__heap_base` for this module (global 2 of the decoded artifact): above
`__data_end` (1049853), so the array cannot overlap the panic strings, and
far above the shadow stack, which grows down from 1048576. -/
def heapBase : UInt32 := 1049856

/-- Entry configuration for the export. `func2` declares four `i32` locals. -/
def config (arr : List UInt32) (target : UInt32) : Wasm.SmallStep.Config Unit :=
  let initial : Store Unit := «module».initialStore
  { expr := .running
      ⟨⟨[.i32 heapBase, .i32 (UInt32.ofNat arr.length), .i32 target],
          [.i32 0, .i32 0, .i32 0, .i32 0], []⟩,
        func2, 1, [], [], []⟩
    store :=
      { runtime := { instances := #[{ module := «module», host := {} }], entry := ⟨0⟩ }
        wasm := { initial with mem := writeWords initial.mem heapBase arr } } }

/-- The binary returns exactly what the model predicts, on this input. -/
private abbrev AgreesOn (arr : List UInt32) (target : UInt32) : Prop :=
  Wasm.SmallStep.TerminatesWith (config arr target)
    (fun values _ => values = [.i32 (searchResult arr target)])

private def sample : List UInt32 := [10, 20, 30, 40, 50]

theorem agrees_hit_middle : AgreesOn sample 30 := by
  apply Wasm.SmallStep.runSteps_checked_terminates (fuel := 2000)
    (fun values _ => decide (values = [.i32 (searchResult sample 30)]))
  · native_decide
  · intro values store h; exact of_decide_eq_true h

theorem agrees_miss_between : AgreesOn sample 35 := by
  apply Wasm.SmallStep.runSteps_checked_terminates (fuel := 2000)
    (fun values _ => decide (values = [.i32 (searchResult sample 35)]))
  · native_decide
  · intro values store h; exact of_decide_eq_true h

theorem agrees_empty : AgreesOn [] 3 := by
  apply Wasm.SmallStep.runSteps_checked_terminates (fuel := 2000)
    (fun values _ => decide (values = [.i32 (searchResult [] 3)]))
  · native_decide
  · intro values store h; exact of_decide_eq_true h

end Project.BinarySearch.Smoke
