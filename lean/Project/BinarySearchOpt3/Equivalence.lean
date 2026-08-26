import Project.BinarySearch.Smoke
import Project.BinarySearchOpt3.Smoke

/-!
# The two artifacts agree, on concrete inputs

`binary_search` compiled at `opt-level = 0` and at `opt-level = 3` from
byte-identical Rust reaches the same observable outcome. The optimizer inlines
the slice construction and the inner call, drops the shadow stack, keeps the
loop state in locals rather than spilling it, and rewrites the division by two
as a shift, so the two modules have very little in common as code.

The observation is deliberately trivial. The result of this function is its
return value, and `ObservableOutcome` already carries that, so nothing is
gained by observing memory. Observing memory would in fact make the statement
false rather than stronger: the unoptimized build writes a shadow-stack frame
that the optimized build never touches.

These are concrete instances, established by running both binaries. The
symbolic statement lives in `SymbolicEquivalence.lean` and does not rest on
them.
-/

namespace Project.BinarySearchOpt3.Equivalence

open Wasm
open Project.BinarySearch.Pure

/-- Nothing about the store is observed; see the module docstring. -/
def noObservation (_ : Wasm.SmallStep.MachineStore Unit) : Unit := ()

private def sample : List UInt32 := [10, 20, 30, 40, 50]

private theorem opt0_outcome (arr : List UInt32) (target : UInt32)
    (r : List Value)
    (h : Wasm.SmallStep.TerminatesWith
      (Project.BinarySearch.Smoke.config arr target) (fun values _ => values = r)) :
    Wasm.SmallStep.TerminatesWith (Project.BinarySearch.Smoke.config arr target)
      (fun values store => values = r ∧ noObservation store = ()) :=
  h.mono (fun _ _ hv => ⟨hv, rfl⟩)

private theorem opt3_outcome (arr : List UInt32) (target : UInt32)
    (r : List Value)
    (h : Wasm.SmallStep.TerminatesWith
      (Project.BinarySearchOpt3.Smoke.config arr target)
      (fun values _ => values = r)) :
    Wasm.SmallStep.TerminatesWith
      (Project.BinarySearchOpt3.Smoke.config arr target)
      (fun values store => values = r ∧ noObservation store = ()) :=
  h.mono (fun _ _ hv => ⟨hv, rfl⟩)

/-- A hit: both artifacts return the same index. -/
theorem equivalent_hit_middle :
    Wasm.SmallStep.ObservationallyEquivOn
      (Project.BinarySearch.Smoke.config sample 30)
      (Project.BinarySearchOpt3.Smoke.config sample 30)
      noObservation :=
  Wasm.SmallStep.ObservationallyEquivOn.of_common_outcome
    (opt0_outcome sample 30 _ Project.BinarySearch.Smoke.agrees_hit_middle)
    (opt3_outcome sample 30 _ Project.BinarySearchOpt3.Smoke.agrees_hit_middle)

/-- A miss: both artifacts return the same sentinel. -/
theorem equivalent_miss_between :
    Wasm.SmallStep.ObservationallyEquivOn
      (Project.BinarySearch.Smoke.config sample 35)
      (Project.BinarySearchOpt3.Smoke.config sample 35)
      noObservation :=
  Wasm.SmallStep.ObservationallyEquivOn.of_common_outcome
    (opt0_outcome sample 35 _ Project.BinarySearch.Smoke.agrees_miss_between)
    (opt3_outcome sample 35 _ Project.BinarySearchOpt3.Smoke.agrees_miss_between)

/-- The empty array, where the two builds differ most: the optimized one tests
the length up front and never enters its loop. -/
theorem equivalent_empty :
    Wasm.SmallStep.ObservationallyEquivOn
      (Project.BinarySearch.Smoke.config [] 3)
      (Project.BinarySearchOpt3.Smoke.config [] 3)
      noObservation :=
  Wasm.SmallStep.ObservationallyEquivOn.of_common_outcome
    (opt0_outcome [] 3 _ Project.BinarySearch.Smoke.agrees_empty)
    (opt3_outcome [] 3 _ Project.BinarySearchOpt3.Smoke.agrees_empty)

end Project.BinarySearchOpt3.Equivalence
