import Project.BinarySearchOpt3.Program
import Project.BinarySearch.Pure

/-!
# Specification for the optimized `binary_search` artifact

The statement: for any array of `u32` words laid out anywhere in the heap
region, running the decoded export terminates and returns exactly what the
pure model returns. Termination is part of the claim, not an assumption, and
the statement is fuel-free.

Two hypotheses, both about layout rather than content:

* `heapBase ≤ ptr` keeps the array clear of the data segments the compiler
  emitted (panic strings, all below `__heap_base`).
* `ptr.toNat + 4 * arr.length ≤ 17 * 65536` keeps the array inside the
  module's 17 pages of linear memory. This single bound also supplies every
  no-wrap fact the address arithmetic needs, and `arr.length < 2^31` with it.

There is deliberately no sortedness hypothesis here: the compiled code
computes the model's recursion whether or not the array is sorted, and the
proof tracks that computation. Sortedness only becomes relevant when
*interpreting* the model's answer (a `-1` means "absent" only for sorted
input), which is what the `terminates_hit` / `terminates_miss` corollaries in
`TotalProof.lean` state.
-/

namespace Project.BinarySearchOpt3.Spec

open Wasm
open Project.BinarySearch.Pure

/-- Place `u32` values at consecutive addresses starting at `base`. -/
def writeWords (m : Mem) (base : UInt32) : List UInt32 → Mem
  | [] => m
  | v :: vs => writeWords (m.write32 base v) (base + 4) vs

/-- `__heap_base` for this module: above every data segment the compiler
emitted. -/
def heapBase : UInt32 := 1049808

/-- Entry configuration for the export, with `arr` laid out at `ptr`.
Same shape as the concrete `Smoke.config`, with the pointer generalized. -/
def symbolicConfig (ptr : UInt32) (arr : List UInt32) (target : UInt32) :
    Wasm.SmallStep.Config Unit :=
  let initial : Store Unit := «module».initialStore
  { expr := .running
      ⟨⟨[.i32 ptr, .i32 (UInt32.ofNat arr.length), .i32 target],
          [.i32 0, .i32 0, .i32 0, .i32 0], []⟩,
        func0, 1, [], [], []⟩
    store :=
      { runtime := { module := «module», host := {} }
        wasm := { initial with mem := writeWords initial.mem ptr arr } } }

/-- Total functional correctness of the compiled artifact: the export
terminates and returns the model's answer, for every array in the heap
region and every target. Proven in `TotalProof.lean`. -/
@[spec_of "rust-exported" "binary_search_opt3::binary_search_opt3"]
def BinarySearchOpt3Spec : Prop :=
  ∀ (ptr : UInt32) (arr : List UInt32) (target : UInt32),
    heapBase ≤ ptr →
    ptr.toNat + 4 * arr.length ≤ 17 * 65536 →
    Wasm.SmallStep.TerminatesWith (symbolicConfig ptr arr target)
      (fun values _ => values = [.i32 (searchResult arr target)])

end Project.BinarySearchOpt3.Spec
