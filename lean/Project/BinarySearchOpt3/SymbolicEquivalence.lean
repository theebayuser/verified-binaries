import Project.BinarySearch.TotalProof
import Project.BinarySearchOpt3.TotalProof
import Project.BinarySearchOpt3.Equivalence

/-!
# The two artifacts agree, symbolically

The concrete instances in `Equivalence.lean` run both binaries on sample
inputs. This file states the universal version: for every array in the heap
region and every target, the unoptimized and the optimized artifact reach the
same observable outcome. The proof runs neither binary. It composes the two
symbolic total-correctness theorems, which each say that their artifact
terminates with `searchResult arr target`, so the common outcome is shared by
construction.

The hypotheses are the ones from the unoptimized specification. Its
`heapBase` (1049856) sits above the optimized module's (1049808), because the
unoptimized build has larger data segments. An array above the higher base is
above both, so one pair of hypotheses serves both specifications.

The observation is `noObservation`, for the reason given in
`Equivalence.lean`: the return value is the result of this function, and the
two builds differ in memory on purpose. The unoptimized build writes
shadow-stack frames that the optimized build never touches, so observing
memory would make the statement false rather than stronger.

Unlike the concrete instances, this theorem carries no `native_decide` axiom.
`docs/check-axioms.py` holds it to the symbolic standard: Lean's standard
axioms plus the one inherited upstream `bv_decide` axiom.
-/

namespace Project.BinarySearchOpt3.SymbolicEquivalence

open Wasm
open Project.BinarySearch.Pure
open Project.BinarySearchOpt3.Equivalence (noObservation)

/-- The two compiled artifacts are observationally equivalent on every array
in the heap region and every target. Byte-identical Rust, `opt-level = 0`
against `opt-level = 3`, one statement. -/
theorem equivalent (ptr : UInt32) (arr : List UInt32) (target : UInt32)
    (hbase : Project.BinarySearch.Spec.heapBase ≤ ptr)
    (hfit : ptr.toNat + 4 * arr.length ≤ 17 * 65536) :
    Wasm.SmallStep.ObservationallyEquivOn
      (Project.BinarySearch.Spec.symbolicConfig ptr arr target)
      (Project.BinarySearchOpt3.Spec.symbolicConfig ptr arr target)
      noObservation := by
  have hbase3 : Project.BinarySearchOpt3.Spec.heapBase ≤ ptr :=
    UInt32.le_trans (by decide) hbase
  have h0 := Project.BinarySearch.TotalProof.binarySearchSpec_holds
    ptr arr target hbase hfit
  have h3 := Project.BinarySearchOpt3.TotalProof.binarySearchOpt3Spec_holds
    ptr arr target hbase3 hfit
  exact Wasm.SmallStep.ObservationallyEquivOn.of_common_outcome
    (h0.mono (fun _ _ hv => ⟨hv, rfl⟩))
    (h3.mono (fun _ _ hv => ⟨hv, rfl⟩))

end Project.BinarySearchOpt3.SymbolicEquivalence
