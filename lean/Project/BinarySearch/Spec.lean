import Project.BinarySearch.Program
import Project.BinarySearch.Pure

/-!
# Specification for the unoptimized `binary_search` artifact

The statement: for any array of `u32` words laid out in the heap region,
running the decoded export terminates and returns exactly what the pure model
returns. Termination is part of the claim, not an assumption, and the
statement is fuel-free.

Two hypotheses, both about layout rather than content:

* `ptr.toNat + 4 * arr.length ≤ 17 * 65536` keeps the array inside the
  module's 17 pages of linear memory. It supplies every no-wrap fact the
  address arithmetic needs.
* `heapBase ≤ ptr` keeps the array clear of the data segments and, unlike in
  the optimized artifact, this hypothesis is load-bearing here: the compiled
  code spills its loop state to two shadow-stack frames below the initial
  stack pointer (1048576), and the proof needs the array cells disjoint from
  those frame cells to own both regions separately.

There is deliberately no sortedness hypothesis; see the optimized artifact's
specification for the rationale, which applies unchanged.
-/

namespace Project.BinarySearch.Spec

open Wasm
open Project.BinarySearch.Pure

/-- Place `u32` values at consecutive addresses starting at `base`. -/
def writeWords (m : Mem) (base : UInt32) : List UInt32 → Mem
  | [] => m
  | v :: vs => writeWords (m.write32 base v) (base + 4) vs

/-- `__heap_base` for this module (global 2 of the decoded artifact): above
`__data_end` (1049853) and far above the shadow-stack region, which grows
down from 1048576. -/
def heapBase : UInt32 := 1049856

/-- Entry configuration for the export (`func2`, which declares four `i32`
locals), with `arr` laid out at `ptr`. -/
def symbolicConfig (ptr : UInt32) (arr : List UInt32) (target : UInt32) :
    Wasm.SmallStep.Config Unit :=
  let initial : Store Unit := «module».initialStore
  { expr := .running
      ⟨⟨[.i32 ptr, .i32 (UInt32.ofNat arr.length), .i32 target],
          [.i32 0, .i32 0, .i32 0, .i32 0], []⟩,
        func2, 1, [], [], []⟩
    store :=
      { runtime := { instances := #[{ module := «module», host := {} }], entry := ⟨0⟩ }
        wasm := { initial with mem := writeWords initial.mem ptr arr } } }

/-- Total functional correctness of the unoptimized compiled artifact: the
export terminates and returns the pure model's answer, for every array in the
heap region and every target. Proven in `TotalProof.lean`. -/
@[spec_of "rust-exported" "binary_search::binary_search"]
def BinarySearchSpec : Prop :=
  ∀ (ptr : UInt32) (arr : List UInt32) (target : UInt32),
    heapBase ≤ ptr →
    ptr.toNat + 4 * arr.length ≤ 17 * 65536 →
    Wasm.SmallStep.TerminatesWith (symbolicConfig ptr arr target)
      (fun values _ => values = [.i32 (searchResult arr target)])

end Project.BinarySearch.Spec
