import Project.BinarySearch.Spec
import Project.BinarySearch.Rules

/-!
# Symbolic total correctness of the unoptimized artifact

Proves `BinarySearchSpec` from `Spec.lean`: for every array laid out in the
heap region and every target, the decoded export terminates and returns
exactly what the pure model returns.

The structure mirrors `Project.BinarySearchOpt3.TotalProof`, with two
additions the unoptimized code demands:

1. **Shadow-stack frames.** The export shim (`func2`) and the inner loop
   (`func0`) each take a 16-byte frame below the initial stack pointer
   (1048576), and the loop keeps its state spilled there rather than in
   locals. The ghost heap therefore covers the eight frame words at
   1048544..1048575 in addition to the array cells. The frame region sits
   below the module's single data segment (offset 1048576), so its initial
   bytes are zero and the ghost cells are *adopted* from the existing
   memory (`adopt32_agrees`) instead of tracking a physical write.
2. **The stack-pointer global.** `global.get 0` / `global.set 0` move the
   frame pointer, so adequacy goes through
   `wasm_smallStep_heap_globals_runtime_store_terminates` with a singleton
   ghost global map for `$__stack_pointer`.
-/

namespace Project.BinarySearch.TotalProof

open Wasm Wasm.SepLogic Wasm.SmallStep
open Iris Iris.Std
open Project.BinarySearch.Pure
open Project.BinarySearch.Spec

set_option maxRecDepth 40000

/-! ## Facts about the entry configuration's store -/

theorem write32_pages (m : Mem) (a v : UInt32) :
    (m.write32 a v).pages = m.pages := rfl

theorem writeWords_pages (m : Mem) (base : UInt32) (vs : List UInt32) :
    (writeWords m base vs).pages = m.pages := by
  induction vs generalizing m base with
  | nil => rfl
  | cons v vs ih =>
      simp only [writeWords]
      rw [ih, write32_pages]

/-- The module allocates 17 pages of linear memory. `rfl` walks the module's
data segment; no axioms are involved. -/
theorem initial_mem_pages :
    ((«module».initialStore : Store Unit)).mem.pages = 17 := rfl

/-- The module declares no extra memories, so the multi-memory resolver of
the adequacy layer collapses to memory 0. -/
theorem initial_extraMems :
    ((«module».initialStore : Store Unit)).extraMems = [] := rfl

/-- Global 0 is `$__stack_pointer`, initialized to 1048576. -/
theorem initial_global0 :
    ((«module».initialStore : Store Unit)).globals.globals[0]? =
      some (.i32 (1048576 : UInt32)) := rfl

/-! ## The ghost byte map: frame words plus the array region -/

/-- Fold `store32Heap` over a list of words, 4 bytes per element. -/
def heap32Aux (heap : WasmHeapMap (Option UInt8)) (base : UInt32) :
    List UInt32 → WasmHeapMap (Option UInt8)
  | [] => heap
  | value :: values => heap32Aux (store32Heap heap 0 base value) (base + 4) values

/-- Base of the shadow-stack region the two frames occupy: `func2`'s frame
at 1048560 and `func0`'s at 1048544. -/
def frameBase : UInt32 := 1048544

/-- The eight frame words, all zero in the initial memory. -/
def frameWords : List UInt32 := List.replicate 8 0

/-- The ghost heap covering the frame words and the array cells of the
entry configuration. -/
def searchHeap (ptr : UInt32) (arr : List UInt32) :
    WasmHeapMap (Option UInt8) :=
  heap32Aux (heap32Aux ∅ frameBase frameWords) ptr arr

/-! ### Adoption: ghost cells over bytes the memory already holds

`heap32Aux_agrees` below tracks a physical `writeWords` alongside the ghost
extension. The frame words need the other mode: the memory already holds
their bytes (zeros below the data segment), so the ghost heap adopts them
without any physical write. -/

theorem adopt32_agrees (σ : WasmHeapMap (Option UInt8)) (mem : Mem)
    (addr value : UInt32)
    (hread : mem.read32 addr = value)
    (h1 : (addr + 1).toNat = addr.toNat + 1)
    (h2 : (addr + 2).toNat = addr.toNat + 2)
    (h3 : (addr + 3).toNat = addr.toNat + 3)
    (hagree : heapAgreesWithMem σ
      (fun id => if id = 0 then some mem else none)) :
    heapAgreesWithMem (store32Heap σ 0 addr value)
      (fun id => if id = 0 then some mem else none) := by
  intro key v hget
  by_cases hk3 : key = ⟨0, addr + 3⟩
  · subst hk3
    rw [store32Heap, get?_insert_eq rfl] at hget
    obtain rfl : u32Byte value 3 = v := by simpa using hget
    exact ⟨mem, by simp, Mem.read32_byte3 hread h3⟩
  rw [store32Heap, get?_insert_ne (Ne.symm hk3)] at hget
  by_cases hk2 : key = ⟨0, addr + 2⟩
  · subst hk2
    rw [get?_insert_eq rfl] at hget
    obtain rfl : u32Byte value 2 = v := by simpa using hget
    exact ⟨mem, by simp, Mem.read32_byte2 hread h2⟩
  rw [get?_insert_ne (Ne.symm hk2)] at hget
  by_cases hk1 : key = ⟨0, addr + 1⟩
  · subst hk1
    rw [get?_insert_eq rfl] at hget
    obtain rfl : u32Byte value 1 = v := by simpa using hget
    exact ⟨mem, by simp, Mem.read32_byte1 hread h1⟩
  rw [get?_insert_ne (Ne.symm hk1)] at hget
  by_cases hk0 : key = ⟨0, addr⟩
  · subst hk0
    rw [get?_insert_eq rfl] at hget
    obtain rfl : u32Byte value 0 = v := by simpa using hget
    exact ⟨mem, by simp, Mem.read32_byte0 hread⟩
  rw [get?_insert_ne (Ne.symm hk0)] at hget
  exact hagree key v hget

theorem adopt32_inBounds (σ : WasmHeapMap (Option UInt8)) (mem : Mem)
    (addr value : UInt32)
    (h1 : (addr + 1).toNat = addr.toNat + 1)
    (h2 : (addr + 2).toNat = addr.toNat + 2)
    (h3 : (addr + 3).toNat = addr.toNat + 3)
    (hbound : addr.toNat + 4 ≤ mem.pages * 65536)
    (hin : heapAddressesInBounds σ
      (fun id => if id = 0 then some mem else none)) :
    heapAddressesInBounds (store32Heap σ 0 addr value)
      (fun id => if id = 0 then some mem else none) := by
  intro key hkey
  by_cases hk3 : key = ⟨0, addr + 3⟩
  · subst hk3
    exact ⟨mem, by simp, by dsimp only; rw [h3]; omega⟩
  rw [store32Heap, get?_insert_ne (Ne.symm hk3)] at hkey
  by_cases hk2 : key = ⟨0, addr + 2⟩
  · subst hk2
    exact ⟨mem, by simp, by dsimp only; rw [h2]; omega⟩
  rw [get?_insert_ne (Ne.symm hk2)] at hkey
  by_cases hk1 : key = ⟨0, addr + 1⟩
  · subst hk1
    exact ⟨mem, by simp, by dsimp only; rw [h1]; omega⟩
  rw [get?_insert_ne (Ne.symm hk1)] at hkey
  by_cases hk0 : key = ⟨0, addr⟩
  · subst hk0
    exact ⟨mem, by simp, by dsimp only; omega⟩
  rw [get?_insert_ne (Ne.symm hk0)] at hkey
  exact hin key hkey

/-! ### Domain: keys added by `heap32Aux` stay inside the seeded window -/

theorem heap32Aux_domain (heap : WasmHeapMap (Option UInt8)) (base : UInt32)
    (values : List UInt32)
    (hfit : base.toNat + 4 * values.length < UInt32.size) :
    ∀ (key : MemoryKey), get? (heap32Aux heap base values) key ≠ none →
      get? heap key ≠ none ∨
        (key.memId = 0 ∧ base.toNat ≤ key.addr.toNat ∧
          key.addr.toNat < base.toNat + 4 * values.length) := by
  induction values generalizing heap base with
  | nil =>
      intro key hkey
      exact .inl hkey
  | cons value values ih =>
      intro key hkey
      simp only [heap32Aux] at hkey
      simp only [List.length_cons] at hfit ⊢
      simp only [UInt32.size] at hfit
      have hn (n : Nat) (_hle : n ≤ 4) :
          (base + UInt32.ofNat n).toNat = base.toNat + n := by
        apply UInt32.add_ofNat_toNat_noWrap base n
        · omega
        · omega
      have hfit' : (base + 4).toNat + 4 * values.length < UInt32.size := by
        change (base + UInt32.ofNat 4).toNat + 4 * values.length < UInt32.size
        rw [hn 4 (by omega)]
        simp only [UInt32.size]
        omega
      rcases ih (store32Heap heap 0 base value) (base + 4) hfit' key hkey with
        hstored | ⟨hm, hlo, hhi⟩
      · by_cases hk3 : key = ⟨0, base + 3⟩
        · subst hk3
          refine .inr ⟨rfl, ?_, ?_⟩ <;>
            · show _
              have := hn 3 (by omega)
              simp only [show (base + 3 : UInt32) = base + UInt32.ofNat 3 from rfl]
              omega
        rw [store32Heap, get?_insert_ne (Ne.symm hk3)] at hstored
        by_cases hk2 : key = ⟨0, base + 2⟩
        · subst hk2
          refine .inr ⟨rfl, ?_, ?_⟩ <;>
            · show _
              have := hn 2 (by omega)
              simp only [show (base + 2 : UInt32) = base + UInt32.ofNat 2 from rfl]
              omega
        rw [get?_insert_ne (Ne.symm hk2)] at hstored
        by_cases hk1 : key = ⟨0, base + 1⟩
        · subst hk1
          refine .inr ⟨rfl, ?_, ?_⟩ <;>
            · show _
              have := hn 1 (by omega)
              simp only [show (base + 1 : UInt32) = base + UInt32.ofNat 1 from rfl]
              omega
        rw [get?_insert_ne (Ne.symm hk1)] at hstored
        by_cases hk0 : key = ⟨0, base⟩
        · subst hk0
          refine .inr ⟨rfl, ?_, ?_⟩ <;> · dsimp only; omega
        rw [get?_insert_ne (Ne.symm hk0)] at hstored
        exact .inl hstored
      · refine .inr ⟨hm, ?_, ?_⟩ <;>
          · have := hn 4 (by omega)
            simp only [show (base + 4 : UInt32) = base + UInt32.ofNat 4 from rfl]
              at hlo hhi
            omega

/-! ### The tracking lemmas, unchanged from the optimized side -/

theorem heap32Aux_agrees
    (heap : WasmHeapMap (Option UInt8)) (mem : Mem) (base : UInt32)
    (values : List UInt32)
    (hagree : heapAgreesWithMem heap
      (fun id => if id = 0 then some mem else none))
    (hfit : base.toNat + 4 * values.length < UInt32.size) :
    heapAgreesWithMem (heap32Aux heap base values)
      (fun id => if id = 0 then some (writeWords mem base values) else none) := by
  induction values generalizing heap mem base with
  | nil => simpa [heap32Aux, writeWords]
  | cons value values ih =>
      simp only [heap32Aux, writeWords, List.length_cons] at *
      simp only [UInt32.size] at hfit
      apply ih
      · apply store32_sound0
        · exact UInt32.add_ofNat_toNat_noWrap base 1 (by decide) (by omega)
        · exact UInt32.add_ofNat_toNat_noWrap base 2 (by decide) (by omega)
        · exact UInt32.add_ofNat_toNat_noWrap base 3 (by decide) (by omega)
        · exact hagree
      · have h4 : (base + 4 : UInt32).toNat = base.toNat + 4 :=
          UInt32.add_ofNat_toNat_noWrap base 4 (by decide) (by omega)
        rw [h4]
        simp only [UInt32.size]
        omega

theorem heap32Aux_inBounds
    (heap : WasmHeapMap (Option UInt8)) (mem : Mem) (base : UInt32)
    (values : List UInt32)
    (hinBounds : heapAddressesInBounds heap
      (fun id => if id = 0 then some mem else none))
    (hfit : base.toNat + 4 * values.length < UInt32.size)
    (hmem : base.toNat + 4 * values.length ≤ mem.pages * 65536) :
    heapAddressesInBounds (heap32Aux heap base values)
      (fun id => if id = 0 then some (writeWords mem base values) else none) := by
  induction values generalizing heap mem base with
  | nil => simpa [heap32Aux, writeWords]
  | cons value values ih =>
      simp only [heap32Aux, writeWords, List.length_cons] at *
      simp only [UInt32.size] at hfit
      have h4 : (base + 4 : UInt32).toNat = base.toNat + 4 :=
        UInt32.add_ofNat_toNat_noWrap base 4 (by decide) (by omega)
      apply ih
      · apply store32_inBounds0
        · exact UInt32.add_ofNat_toNat_noWrap base 1 (by decide) (by omega)
        · exact UInt32.add_ofNat_toNat_noWrap base 2 (by decide) (by omega)
        · exact UInt32.add_ofNat_toNat_noWrap base 3 (by decide) (by omega)
        · omega
        · exact hinBounds
      · rw [h4]
        simp only [UInt32.size]
        omega
      · rw [write32_pages, h4]
        omega

set_option maxHeartbeats 2000000 in
theorem heap32Aux_pointsTo [WasmHeapGS Unit]
    (heap : WasmHeapMap (Option UInt8)) (base : UInt32)
    (values : List UInt32)
    (hdisjoint : ∀ (key : MemoryKey) byte, get? heap key = some byte →
      key.addr.toNat < base.toNat)
    (hfit : base.toNat + 4 * values.length < UInt32.size) :
    ([∗map] address ↦ value ∈ heap32Aux heap base values,
      pointsTo (GF := WasmHeapGF Unit) (H := WasmHeapMap)
        address (DFrac.own 1) value) ⊢
      arrayAt 0 base values ∗
      ([∗map] address ↦ value ∈ heap,
        pointsTo (GF := WasmHeapGF Unit) (H := WasmHeapMap)
          address (DFrac.own 1) value) := by
  induction values generalizing heap base with
  | nil =>
      simp only [heap32Aux, arrayAt, BI.emp_sep.to_eq]
      iintro Hheap
      iexact Hheap
  | cons value values ih =>
      simp only [heap32Aux, List.length_cons] at *
      simp only [UInt32.size] at hfit
      have hn (n : Nat) (_hle : n ≤ 4) :
          (base + UInt32.ofNat n).toNat = base.toNat + n := by
        apply UInt32.add_ofNat_toNat_noWrap base n
        · omega
        · omega
      have hn4 := hn 4 (by omega)
      have hl1 : (base + 1 : UInt32).toNat = base.toNat + 1 := by
        apply UInt32.add_ofNat_toNat_noWrap base 1 (by decide)
        omega
      have hl2 : (base + 2 : UInt32).toNat = base.toNat + 2 := by
        apply UInt32.add_ofNat_toNat_noWrap base 2 (by decide)
        omega
      have hl3 : (base + 3 : UInt32).toNat = base.toNat + 3 := by
        apply UInt32.add_ofNat_toNat_noWrap base 3 (by decide)
        omega
      have hget (n : Nat) (_hlt : n < 4) :
          get? heap ⟨0, base + UInt32.ofNat n⟩ = none := by
        by_contra h
        obtain ⟨byte, hbyte⟩ := Option.ne_none_iff_exists.mp h
        have hlt := hdisjoint _ _ hbyte.symm
        dsimp only at hlt
        rw [hn n (by omega)] at hlt
        omega
      have hget0 : get? heap ⟨0, base⟩ = none := by
        simpa using hget 0 (by omega)
      have hgetL1 : get? heap ⟨0, base + 1⟩ = none := by
        simpa using hget 1 (by omega)
      have hgetL2 : get? heap ⟨0, base + 2⟩ = none := by
        simpa using hget 2 (by omega)
      have hgetL3 : get? heap ⟨0, base + 3⟩ = none := by
        simpa using hget 3 (by omega)
      have hdisjoint' : ∀ (key : MemoryKey) byte,
          get? (store32Heap heap 0 base value) key = some byte →
          key.addr.toNat < (base + 4).toNat := by
        intro key byte hkey
        change key.addr.toNat < (base + UInt32.ofNat 4).toNat
        rw [hn4]
        by_cases h3 : key = ⟨0, base + 3⟩
        · subst key; show (base + 3 : UInt32).toNat < base.toNat + 4
          rw [hl3]; omega
        by_cases h2 : key = ⟨0, base + 2⟩
        · subst key; show (base + 2 : UInt32).toNat < base.toNat + 4
          rw [hl2]; omega
        by_cases h1 : key = ⟨0, base + 1⟩
        · subst key; show (base + 1 : UInt32).toNat < base.toNat + 4
          rw [hl1]; omega
        by_cases h0 : key = ⟨0, base⟩
        · subst key; show (base : UInt32).toNat < base.toNat + 4
          omega
        simp only [store32Heap, get?_insert_ne (Ne.symm h3),
          get?_insert_ne (Ne.symm h2), get?_insert_ne (Ne.symm h1),
          get?_insert_ne (Ne.symm h0)] at hkey
        have hlt := hdisjoint key byte hkey
        omega
      have hfit' : (base + 4).toNat + 4 * values.length < UInt32.size := by
        change (base + UInt32.ofNat 4).toNat + 4 * values.length < UInt32.size
        rw [hn4]
        simp only [UInt32.size]
        omega
      iintro Hheap
      ihave Hsplit := ih (store32Heap heap 0 base value) (base + 4)
        hdisjoint' hfit' $$ Hheap
      icases Hsplit with ⟨Hvalues, Hstored⟩
      ihave Hword := store32Heap_pointsTo heap 0 base value
        hget0 hgetL1 hgetL2 hgetL3 hl1 hl2 hl3 $$ Hstored
      icases Hword with ⟨Hword, Hheap⟩
      simp only [arrayAt]
      isplitl [Hword Hvalues]
      · isplitl [Hword]
        · iexact Hword
        · iexact Hvalues
      · iexact Hheap

/-! ## The three faces of `searchHeap` at the entry configuration -/

/-- The frame region agrees with the initial memory: every frame word reads
zero, because the region sits below the module's single data segment. -/
theorem frameHeap_agrees :
    heapAgreesWithMem (heap32Aux ∅ frameBase frameWords)
      (fun id => if id = 0 then
        some ((«module».initialStore : Store Unit)).mem else none) := by
  simp only [frameWords, frameBase, List.replicate, heap32Aux]
  apply adopt32_agrees _ _ _ _ (by rfl) (by decide) (by decide) (by decide)
  apply adopt32_agrees _ _ _ _ (by rfl) (by decide) (by decide) (by decide)
  apply adopt32_agrees _ _ _ _ (by rfl) (by decide) (by decide) (by decide)
  apply adopt32_agrees _ _ _ _ (by rfl) (by decide) (by decide) (by decide)
  apply adopt32_agrees _ _ _ _ (by rfl) (by decide) (by decide) (by decide)
  apply adopt32_agrees _ _ _ _ (by rfl) (by decide) (by decide) (by decide)
  apply adopt32_agrees _ _ _ _ (by rfl) (by decide) (by decide) (by decide)
  apply adopt32_agrees _ _ _ _ (by rfl) (by decide) (by decide) (by decide)
  exact heapAgreesWithMem_empty _

theorem frameHeap_inBounds :
    heapAddressesInBounds (heap32Aux ∅ frameBase frameWords)
      (fun id => if id = 0 then
        some ((«module».initialStore : Store Unit)).mem else none) := by
  simp only [frameWords, frameBase, List.replicate, heap32Aux]
  have hpages := initial_mem_pages
  apply adopt32_inBounds _ _ _ _ (by decide) (by decide) (by decide)
    (by rw [hpages]; decide)
  apply adopt32_inBounds _ _ _ _ (by decide) (by decide) (by decide)
    (by rw [hpages]; decide)
  apply adopt32_inBounds _ _ _ _ (by decide) (by decide) (by decide)
    (by rw [hpages]; decide)
  apply adopt32_inBounds _ _ _ _ (by decide) (by decide) (by decide)
    (by rw [hpages]; decide)
  apply adopt32_inBounds _ _ _ _ (by decide) (by decide) (by decide)
    (by rw [hpages]; decide)
  apply adopt32_inBounds _ _ _ _ (by decide) (by decide) (by decide)
    (by rw [hpages]; decide)
  apply adopt32_inBounds _ _ _ _ (by decide) (by decide) (by decide)
    (by rw [hpages]; decide)
  apply adopt32_inBounds _ _ _ _ (by decide) (by decide) (by decide)
    (by rw [hpages]; decide)
  exact heapAddressesInBounds_empty _

theorem searchHeap_agrees (ptr : UInt32) (arr : List UInt32)
    (hfit : ptr.toNat + 4 * arr.length < UInt32.size) :
    heapAgreesWithMem (searchHeap ptr arr)
      (fun id => if id = 0 then
        some (writeWords ((«module».initialStore : Store Unit)).mem ptr arr)
      else none) :=
  heap32Aux_agrees _ _ ptr arr frameHeap_agrees hfit

theorem searchHeap_inBounds (ptr : UInt32) (arr : List UInt32)
    (hfit : ptr.toNat + 4 * arr.length < UInt32.size)
    (hmem : ptr.toNat + 4 * arr.length ≤
      ((«module».initialStore : Store Unit)).mem.pages * 65536) :
    heapAddressesInBounds (searchHeap ptr arr)
      (fun id => if id = 0 then
        some (writeWords ((«module».initialStore : Store Unit)).mem ptr arr)
      else none) :=
  heap32Aux_inBounds _ _ ptr arr frameHeap_inBounds hfit hmem

/-- Keys of the frame region sit below any heap-region pointer. -/
theorem frameHeap_below (ptr : UInt32) (hbase : heapBase ≤ ptr) :
    ∀ (key : MemoryKey) byte,
      get? (heap32Aux ∅ frameBase frameWords) key = some byte →
      key.addr.toNat < ptr.toNat := by
  intro key byte hkey
  have hdom := heap32Aux_domain ∅ frameBase frameWords (by decide) key
    (by simp [hkey])
  rcases hdom with habs | ⟨_, _, hhi⟩
  · exact absurd (get?_empty key) habs
  · have hptr : heapBase.toNat ≤ ptr.toNat := UInt32.le_iff_toNat_le.mp hbase
    have hhb : heapBase.toNat = 1049856 := rfl
    have hfb : frameBase.toNat + 4 * frameWords.length = 1048576 := rfl
    omega

theorem searchHeap_pointsTo [WasmHeapGS Unit]
    (ptr : UInt32) (arr : List UInt32)
    (hbase : heapBase ≤ ptr)
    (hfit : ptr.toNat + 4 * arr.length < UInt32.size) :
    ([∗map] address ↦ value ∈ searchHeap ptr arr,
      pointsTo (GF := WasmHeapGF Unit) (H := WasmHeapMap)
        address (DFrac.own 1) value) ⊢
      arrayAt 0 ptr arr ∗ arrayAt 0 frameBase frameWords := by
  unfold searchHeap
  iintro Hheap
  ihave Hsplit := heap32Aux_pointsTo (heap32Aux ∅ frameBase frameWords)
    ptr arr (frameHeap_below ptr hbase) hfit $$ Hheap
  icases Hsplit with ⟨Harray, Hframe⟩
  ihave Hf := heap32Aux_pointsTo ∅ frameBase frameWords
    (fun key byte hget => by simp [get?_empty] at hget)
    (by decide) $$ Hframe
  icases Hf with ⟨Hframe, _Hempty⟩
  isplitl [Harray]
  · iexact Harray
  · iexact Hframe

/-! ## `UInt32` arithmetic bridges

The same bridges as on the optimized side (they are `private` there), plus
one flipped variant: this artifact pushes the midpoint operands in the
opposite order, so the machine's sum is `((hi - lo) >>u 1) + lo`, not
`lo + ((hi - lo) >>u 1)`. -/

private theorem usize_eq : UInt32.size = 4294967296 := rfl

private theorem u32_not_le {a b : UInt32} (h : a < b) : ¬ b ≤ a := by
  rw [UInt32.le_iff_toNat_le]
  rw [UInt32.lt_iff_toNat_lt] at h
  omega

private theorem nat_lt_u32_iff {left right : Nat}
    (hl : left < UInt32.size) (hr : right < UInt32.size) :
    UInt32.ofNat left < UInt32.ofNat right ↔ left < right := by
  rw [UInt32.lt_iff_toNat_lt, UInt32.toNat_ofNat_of_lt' hl,
    UInt32.toNat_ofNat_of_lt' hr]

private theorem one_add_ofNat (n : Nat) :
    1 + UInt32.ofNat n = UInt32.ofNat (n + 1) := by
  rw [UInt32.add_comm, UInt32.ofNat_add]
  rfl

/-- The compiled midpoint `lo + ((hi - lo) >>u 1)` is the model's
`mid lo hi`, provided `lo ≤ hi < 2^32` so the subtraction is genuine. -/
private theorem mid32_eq {lo hi : Nat} (hle : lo ≤ hi)
    (hhi : hi < UInt32.size) :
    UInt32.ofNat lo + (UInt32.ofNat hi - UInt32.ofNat lo) >>> ((1 : UInt32) % 32)
      = UInt32.ofNat (mid lo hi) := by
  have hhiN : hi < 4294967296 := by rw [← usize_eq]; exact hhi
  have hlo : lo < UInt32.size := Nat.lt_of_le_of_lt hle hhi
  have hmid_le : mid lo hi ≤ hi := by unfold mid; omega
  have hsuble : UInt32.ofNat lo ≤ UInt32.ofNat hi := by
    rw [UInt32.le_iff_toNat_le, UInt32.toNat_ofNat_of_lt' hlo,
      UInt32.toNat_ofNat_of_lt' hhi]
    exact hle
  apply UInt32.toNat_inj.mp
  rw [UInt32.toNat_add, UInt32.toNat_shiftRight,
    UInt32.toNat_sub_of_le _ _ hsuble,
    UInt32.toNat_ofNat_of_lt' hlo, UInt32.toNat_ofNat_of_lt' hhi,
    UInt32.toNat_ofNat_of_lt' (Nat.lt_of_le_of_lt hmid_le hhi),
    show ((1 : UInt32) % 32).toNat % 32 = 1 from rfl,
    Nat.shiftRight_eq_div_pow, Nat.pow_one,
    Nat.mod_eq_of_lt (by unfold mid at *; omega)]
  rfl

/-- The operand order this artifact emits: shifted difference first. -/
private theorem mid32_eq' {lo hi : Nat} (hle : lo ≤ hi)
    (hhi : hi < UInt32.size) :
    (UInt32.ofNat hi - UInt32.ofNat lo) >>> ((1 : UInt32) % 32) + UInt32.ofNat lo
      = UInt32.ofNat (mid lo hi) := by
  rw [UInt32.add_comm]
  exact mid32_eq hle hhi

/-- The address the compiled code computes, in the shape `arrayAt` indexes
by: `(mid <<u 2) + ptr = ptr + 4 * mid`. -/
private theorem shl2_add_ptr (ptr index : UInt32) :
    index <<< ((2 : UInt32) % 32) + ptr = ptr + 4 * index := by
  have h4 : index <<< ((2 : UInt32) % 32) = 4 * index := by
    apply UInt32.toNat_inj.mp
    rw [UInt32.toNat_shiftLeft, UInt32.toNat_mul,
      show ((2 : UInt32) % 32).toNat % 32 = 2 from rfl,
      Nat.shiftLeft_eq, show (4 : UInt32).toNat = 4 from rfl]
    omega
  rw [h4, UInt32.add_comm]

/-- Cell addresses inside the 17-page bound do not wrap. -/
private theorem arrayAddress32_toNat (ptr : UInt32) {length : Nat}
    (hfit : ptr.toNat + 4 * length ≤ 17 * 65536) {index : Nat}
    (hindex : index < length) :
    (ptr + 4 * UInt32.ofNat index).toNat = ptr.toNat + 4 * index := by
  have hof : (UInt32.ofNat index).toNat = index := by
    apply UInt32.toNat_ofNat_of_lt'
    rw [usize_eq]
    omega
  rw [UInt32.toNat_add, UInt32.toNat_mul,
    show (4 : UInt32).toNat = 4 from rfl, hof]
  omega

/-- The `i32.and` with 1 that normalizes each comparison result is the
identity on the two values comparisons produce. -/
private theorem and_one_zero : (0 : UInt32) &&& 1 = 0 := rfl

private theorem and_one_one : (1 : UInt32) &&& 1 = 1 := rfl

/-! ## The compiled control flow, named

`func0` is a top-tested loop inside one outer block, with seven nested
blocks inside the loop body encoding the three-way comparison and the two
(unreachable) panic edges. Every equation is `rfl` against `Program.lean`,
so the names cannot drift from the artifact. -/

/-- The panic call the bounds checks guard: never reached symbolically. -/
def panicTail (message : UInt32) : Program :=
  [.localGet 4, .localGet 1, .const message, .call 54, .unreachable]

/-- The loop's top test: exit the whole search with `-1` once `lo ≥ hi`. -/
def testBody : Program :=
  [.localGet 3, .load32 (8 : UInt32), .localGet 3, .load32 (12 : UInt32),
   .ltU, .const (1 : UInt32), .and, .br_if 0,
   .localGet 3, .const (4294967295 : UInt32), .store32 (4 : UInt32),
   .br 2]

/-- Innermost block: bounds-check `mid`, load `arr[mid]`, test `<`. -/
def b7Body : Program :=
  [.localGet 4, .localGet 1, .ltU, .const (1 : UInt32), .and, .eqz,
   .br_if 0,
   .localGet 0, .localGet 4, .const (2 : UInt32), .shl, .add,
   .load32 (0 : UInt32), .localGet 2, .ltU, .const (1 : UInt32), .and,
   .br_if 2, .br 1]

/-- Block 6: falling out of block 7 reaches the first panic call. -/
def b6Body : Program :=
  .block 0 0 b7Body [] [] :: panicTail 1048604

/-- Block 5: the redundant re-test of `mid < len` the compiler emits. -/
def b5Body : Program :=
  .block 0 0 b6Body [] [] ::
    [.localGet 4, .localGet 1, .ltU, .const (1 : UInt32), .and,
     .br_if 1, .br 2]

/-- Block 4: its continuation is the go-right update `lo := mid + 1`. -/
def b4Body : Program :=
  .block 0 0 b5Body [] [] ::
    [.localGet 3, .localGet 4, .const (1 : UInt32), .add,
     .store32 (8 : UInt32), .br 4]

/-- Block 3: reload `arr[mid]` and test `>`. -/
def b3Body : Program :=
  .block 0 0 b4Body [] [] ::
    [.localGet 0, .localGet 4, .const (2 : UInt32), .shl, .add,
     .load32 (0 : UInt32), .localGet 2, .gtU, .const (1 : UInt32), .and,
     .br_if 2, .br 1]

/-- Block 2: falling out of block 3 reaches the second panic call. -/
def b2Body : Program :=
  .block 0 0 b3Body [] [] :: panicTail 1048620

/-- Block 1: its continuation stores the hit `result := mid` and exits. -/
def b1Body : Program :=
  .block 0 0 b2Body [] [] ::
    [.localGet 3, .localGet 4, .store32 (4 : UInt32), .br 2]

/-- One loop iteration: test, compute `mid` into local 4, compare; the
trailing continuation is the go-left update `hi := mid` and the back edge. -/
def loopBody : Program :=
  .block 0 0 testBody [] [] ::
    [.localGet 3, .load32 (8 : UInt32), .localGet 3, .load32 (12 : UInt32),
     .localGet 3, .load32 (8 : UInt32), .sub, .const (1 : UInt32), .shrU,
     .add, .localSet 4,
     .block 0 0 b1Body [] [],
     .localGet 3, .localGet 4, .store32 (12 : UInt32), .br 0]

/-- `func0` after the outer block: load the result slot, pop the frame,
return. -/
def epilogue0 : Program :=
  [.localGet 3, .load32 (4 : UInt32), .localSet 5,
   .localGet 3, .const (16 : UInt32), .add, .globalSet 0,
   .localGet 5, .ret]

/-- The decomposition is definitional against the decoded artifact. -/
theorem func0_eq : func0 =
    [.globalGet 0, .const (16 : UInt32), .sub, .localSet 3,
     .localGet 3, .globalSet 0,
     .localGet 3, .const (0 : UInt32), .store32 (8 : UInt32),
     .localGet 3, .localGet 1, .store32 (12 : UInt32),
     .block 0 0 [.loop 0 0 loopBody [] []] [] []] ++ epilogue0 := rfl

/-- Frame pushed on entering the outer block; falling out (a hit or the
top-test miss, both via `br 2`) resumes at the epilogue. The operand stack
is empty there, so `belowStack` is `[]`. -/
def outerFrame : ControlFrame :=
  { kind := .block, paramArity := 0, resultArity := 0,
    body := [.loop 0 0 loopBody [] []], continuation := epilogue0,
    belowStack := [] }

/-- `func2` after `call 0`: store the result in local 6, pop the shim
frame, return it. -/
def func2Tail : Program :=
  [.localSet 6, .localGet 3, .const (16 : UInt32), .add, .globalSet 0,
   .localGet 6, .ret]

/-- The decomposition of the export shim. -/
theorem func2_eq : func2 =
    [.globalGet 0, .const (16 : UInt32), .sub, .localSet 3,
     .localGet 3, .globalSet 0,
     .const (1048668 : UInt32), .localSet 4,
     .localGet 3, .const (8 : UInt32), .add,
     .localGet 0, .localGet 1, .localGet 4, .call 1,
     .localGet 3, .load32 (12 : UInt32), .localSet 5,
     .localGet 3, .load32 (8 : UInt32), .localGet 5, .localGet 2,
     .call 0] ++ func2Tail := rfl

/-- The call frame `func2` leaves behind at `call 0`: locals with the
frame pointer 1048560 and the reloaded length, continuation `func2Tail`. -/
@[reducible] def func2Caller (ptr len32 target : UInt32) : CallFrame :=
  { locals := ⟨[.i32 ptr, .i32 len32, .i32 target],
      [.i32 1048560, .i32 1048668, .i32 len32, .i32 0], []⟩,
    continuation := func2Tail,
    resultArity := 1, callerRemainder := [], control := [],
    returningInstance := ⟨0⟩ }

/-- Split the adopted frame region into the five cells the two functions
touch: the result slot, `lo`, `hi`, and the shim's two slice slots.
The three remaining words are discarded (the logic is affine). -/
theorem frame_cells [WasmHeapGS Unit] :
    arrayAt 0 frameBase frameWords ⊢
      pointsTo_u32 0 1048548 0 ∗ pointsTo_u32 0 1048552 0 ∗
        pointsTo_u32 0 1048556 0 ∗ pointsTo_u32 0 1048568 0 ∗
        pointsTo_u32 0 1048572 0 := by
  simp only [frameWords, frameBase, List.replicate, arrayAt,
    show (1048544 : UInt32) + 4 = 1048548 from rfl,
    show (1048548 : UInt32) + 4 = 1048552 from rfl,
    show (1048552 : UInt32) + 4 = 1048556 from rfl,
    show (1048556 : UInt32) + 4 = 1048560 from rfl,
    show (1048560 : UInt32) + 4 = 1048564 from rfl,
    show (1048564 : UInt32) + 4 = 1048568 from rfl,
    show (1048568 : UInt32) + 4 = 1048572 from rfl]
  iintro ⟨_H0, H4, H8, H12, _H16, _H20, H24, H28, _⟩
  isplitl [H4]
  · iexact H4
  isplitl [H8]
  · iexact H8
  isplitl [H12]
  · iexact H12
  isplitl [H24]
  · iexact H24
  iexact H28

/-! ## The focused load rule and the shared exit path -/

section WasmProof

open Iris.ProgramLogic Language.Notation

variable [WasmSmallStepGS hlc Unit]
local instance instBinarySearchTotalIrisGS :
    IrisGS_gen hlc (Expr Unit) (WasmHeapGF Unit) :=
  instIrisGS
variable {s : Stuckness} {E : CoPset}
variable {Φ : List Value → IProp (WasmHeapGF Unit)}

/-- Load cell `k` of an owned array: `twp_load32` focused through
`arrayAt_get`, with every no-wrap side condition discharged from the
17-page layout bound. -/
theorem twp_load32_cell
    {params localValues values : List Value}
    {code : Program} {arity : Nat} {remainder : List Value}
    {controls : List ControlFrame} {calls : List CallFrame}
    (ptr : UInt32) (xs : List UInt32) (k : Nat) (hk : k < xs.length)
    (hfit : ptr.toNat + 4 * xs.length ≤ 17 * 65536) :
    arrayAt 0 ptr xs ∗
      (arrayAt 0 ptr xs -∗
        WP (.running ⟨⟨params, localValues, .i32 xs[k] :: values⟩,
            code, arity, remainder, controls, calls⟩ : Expr Unit)
          @ s; E [{ Φ }]) ⊢
    WP (.running ⟨⟨params, localValues,
          .i32 (ptr + 4 * UInt32.ofNat k) :: values⟩,
        .load32 0 :: code, arity, remainder, controls, calls⟩ : Expr Unit)
      @ s; E [{ Φ }] := by
  have haddr : (ptr + 4 * UInt32.ofNat k).toNat = ptr.toNat + 4 * k :=
    arrayAddress32_toNat ptr hfit hk
  have h1 : (ptr + 4 * UInt32.ofNat k + 1).toNat
      = (ptr + 4 * UInt32.ofNat k).toNat + 1 := by
    apply UInt32.add_ofNat_toNat_noWrap _ 1 (by decide)
    omega
  have h2 : (ptr + 4 * UInt32.ofNat k + 2).toNat
      = (ptr + 4 * UInt32.ofNat k).toNat + 2 := by
    apply UInt32.add_ofNat_toNat_noWrap _ 2 (by decide)
    omega
  have h3 : (ptr + 4 * UInt32.ofNat k + 3).toNat
      = (ptr + 4 * UInt32.ofNat k).toNat + 3 := by
    apply UInt32.add_ofNat_toNat_noWrap _ 3 (by decide)
    omega
  iintro ⟨Harray, Htwp⟩
  ihave Hcell := arrayAt_get 0 ptr xs k hk $$ Harray
  icases Hcell with ⟨Hword, Hrestore⟩
  ihave Hword' : pointsTo_u32 0 (ptr + 4 * UInt32.ofNat k + 0) xs[k] $$ [Hword]
  · rw [UInt32.add_zero]
    iexact Hword
  iapply Wasm.SmallStep.twp_load32
    (address := ptr + 4 * UInt32.ofNat k) (offset := 0)
    xs[k] (by simp)
    (by simpa using h1) (by simpa using h2) (by simpa using h3) $$ Hword'
  iintro Hword
  rw [UInt32.add_zero]
  iapply Htwp
  iapply Hrestore
  iexact Hword

/-- The converged exit path: both loop exits land at `epilogue0` with the
answer in the result slot. Pop `func0`'s frame, return into `func2`, pop
its frame, return the answer to the host. -/
theorem twp_searchExit
    (ptr len32 target result l4v : UInt32) (arr : List UInt32)
    (hresult : result = searchResult arr target) :
    (pointsTo_u32 0 ((1048544 : UInt32) + 4) result ∗
      globalPointsToAt 0 0 (.i32 1048544) ∗
      runtimeModuleOwn ⟨0⟩ «module») ⊢
    WP (.running
      ⟨⟨[.i32 ptr, .i32 len32, .i32 target],
          [.i32 1048544, .i32 l4v, .i32 0], []⟩,
        epilogue0, 1, [], [], [func2Caller ptr len32 target]⟩ : Expr Unit)
      @ s; E
      [{ values,
        ∀ (store : MachineStore Unit) (_observations : List StepKind),
          stateInterp (GF := WasmHeapGF Unit) store 0 [] 0 -∗
          ⌜values = [.i32 (searchResult arr target)]⌝ }] := by
  iintro ⟨Hres, HSP, Hruntime⟩
  simp only [epilogue0, func2Caller]
  iapply Wasm.SmallStep.twp_localGet rfl
  iapply Wasm.SmallStep.twp_load32 result
    (by decide) (by decide) (by decide) (by decide) $$ Hres
  iintro _Hres
  iapply Wasm.SmallStep.twp_localSet rfl
  simp only [List.length_cons, List.length_nil, Nat.reduceAdd,
    Nat.reduceSub, List.set]
  iapply Wasm.SmallStep.twp_localGet rfl
  iapply Wasm.SmallStep.twp_const
  iapply Wasm.SmallStep.twp_add
  rw [show (16 : UInt32) + 1048544 = 1048560 by decide]
  iapply Wasm.SmallStep.twp_globalSet $$ HSP
  iintro HSP
  iapply Wasm.SmallStep.twp_localGet rfl
  iapply Wasm.SmallStep.twp_returnFromCallExplicit $$ Hruntime
  iintro _Hruntime
  simp only [List.take, List.singleton_append]
  simp only [func2Tail]
  iapply Wasm.SmallStep.twp_localSet rfl
  simp only [List.length_cons, List.length_nil, Nat.reduceAdd,
    Nat.reduceSub, List.set]
  iapply Wasm.SmallStep.twp_localGet rfl
  iapply Wasm.SmallStep.twp_const
  iapply Wasm.SmallStep.twp_add
  rw [show (16 : UInt32) + 1048560 = 1048576 by decide]
  iapply Wasm.SmallStep.twp_globalSet $$ HSP
  iintro _HSP
  iapply Wasm.SmallStep.twp_localGet rfl
  iapply Wasm.SmallStep.twp_returnFromFunction
  simp only [List.take, List.append_nil]
  iapply twp.value rfl
  iintro %store %observations _Hstate
  ipureintro
  rw [hresult]

/-! ## The loop state and the main symbolic run -/

/-- `func0`'s locals during the loop: the frame pointer in local 3, the
last midpoint in local 4, and local 5 still zero until the epilogue. -/
def searchLocals0 (ptr len32 target midv : UInt32) : Locals :=
  ⟨[.i32 ptr, .i32 len32, .i32 target],
    [.i32 1048544, .i32 midv, .i32 0], []⟩

/-- Loop induction state: the live window, plus the junk value the previous
iteration left in local 4. -/
structure SearchState where
  lo : Nat
  hi : Nat
  midv : UInt32

set_option maxHeartbeats 8000000 in
/-- The full symbolic run of the export: both shadow-stack frames, the
`from_raw_parts` call, and the memory-spilled loop, ending in the model's
answer. The loop invariant owns the array, the three live frame cells, the
stack-pointer global, and the runtime module. -/
theorem twp_searchCall
    (ptr : UInt32) (arr : List UInt32) (target : UInt32)
    (hbase : heapBase ≤ ptr)
    (hfit : ptr.toNat + 4 * arr.length ≤ 17 * 65536) :
    (([∗map] address ↦ value ∈ searchHeap ptr arr,
        pointsTo (GF := WasmHeapGF Unit) (H := WasmHeapMap)
          address (DFrac.own 1) value) ∗
      globalPointsToAt 0 0 (.i32 1048576) ∗
      runtimeModuleOwn ⟨0⟩ «module») ⊢
      WP (symbolicConfig ptr arr target).expr @ Stuckness.NotStuck; ⊤
        [{ values,
          ∀ (store : MachineStore Unit) (_observations : List StepKind),
            stateInterp (GF := WasmHeapGF Unit) store 0 [] 0 -∗
            ⌜values = [.i32 (searchResult arr target)]⌝ }] := by
  iintro ⟨Hheap, HSP, Hruntime⟩
  have hlenS : arr.length < UInt32.size := by rw [usize_eq]; omega
  ihave Hcells := searchHeap_pointsTo ptr arr hbase
    (by rw [usize_eq]; omega) $$ Hheap
  icases Hcells with ⟨Harray, Hframe⟩
  ihave Hfive := frame_cells $$ Hframe
  icases Hfive with ⟨Hres, Hlo, Hhi, Hptrslot, Hlenslot⟩
  simp only [symbolicConfig, func2_eq, List.cons_append, List.nil_append]
  -- `func2` prologue: carve its frame at 1048560.
  iapply Wasm.SmallStep.twp_globalGet $$ HSP
  iintro HSP
  iapply Wasm.SmallStep.twp_const
  iapply Wasm.SmallStep.twp_sub
  rw [show (1048576 : UInt32) - 16 = 1048560 by decide]
  iapply Wasm.SmallStep.twp_localSet rfl
  simp only [List.length_cons, List.length_nil, Nat.reduceAdd,
    Nat.reduceSub, List.set]
  iapply Wasm.SmallStep.twp_localGet rfl
  iapply Wasm.SmallStep.twp_globalSet $$ HSP
  iintro HSP
  iapply Wasm.SmallStep.twp_const
  iapply Wasm.SmallStep.twp_localSet rfl
  simp only [List.length_cons, List.length_nil, Nat.reduceAdd,
    Nat.reduceSub, List.set]
  iapply Wasm.SmallStep.twp_localGet rfl
  iapply Wasm.SmallStep.twp_const
  iapply Wasm.SmallStep.twp_add
  rw [show (8 : UInt32) + 1048560 = 1048568 by decide]
  iapply Wasm.SmallStep.twp_localGet rfl
  iapply Wasm.SmallStep.twp_localGet rfl
  iapply Wasm.SmallStep.twp_localGet rfl
  -- `call 1`: the `from_raw_parts` shim writes the slice pair.
  iapply Wasm.SmallStep.twp_call «module» 1 func1Def
    (by simp [«module»]) (by simp [«module»]) $$ Hruntime
  iintro Hruntime
  simp [func1Def, func1, Function.toLocals, Function.numParams]
  iapply Wasm.SmallStep.twp_localGet rfl
  iapply Wasm.SmallStep.twp_localGet rfl
  ihave Hlenslot' : pointsTo_u32 0 ((1048568 : UInt32) + 4) 0 $$ [Hlenslot]
  · rw [show (1048568 : UInt32) + 4 = 1048572 by decide]
    iexact Hlenslot
  iapply Wasm.SmallStep.twp_store32 0
    (by decide) (by decide) (by decide) (by decide) $$ Hlenslot'
  iintro Hlenslot
  iapply Wasm.SmallStep.twp_localGet rfl
  iapply Wasm.SmallStep.twp_localGet rfl
  ihave Hptrslot' : pointsTo_u32 0 ((1048568 : UInt32) + 0) 0 $$ [Hptrslot]
  · rw [show (1048568 : UInt32) + 0 = 1048568 by decide]
    iexact Hptrslot
  iapply Wasm.SmallStep.twp_store32 0
    (by decide) (by decide) (by decide) (by decide) $$ Hptrslot'
  iintro Hptrslot
  iapply Wasm.SmallStep.twp_returnFromCallExplicit $$ Hruntime
  iintro Hruntime
  simp only [List.take, List.nil_append]
  -- Reload the slice length and pointer from the pair.
  iapply Wasm.SmallStep.twp_localGet rfl
  ihave Hlenslot' : pointsTo_u32 0 ((1048560 : UInt32) + 12)
      (UInt32.ofNat arr.length) $$ [Hlenslot]
  · rw [show (1048560 : UInt32) + 12 = 1048568 + 4 by decide]
    iexact Hlenslot
  iapply Wasm.SmallStep.twp_load32 (UInt32.ofNat arr.length)
    (by decide) (by decide) (by decide) (by decide) $$ Hlenslot'
  iintro _Hlenslot
  iapply Wasm.SmallStep.twp_localSet rfl
  simp only [List.length_cons, List.length_nil, Nat.reduceAdd,
    Nat.reduceSub, List.set]
  iapply Wasm.SmallStep.twp_localGet rfl
  ihave Hptrslot' : pointsTo_u32 0 ((1048560 : UInt32) + 8) ptr $$ [Hptrslot]
  · rw [show (1048560 : UInt32) + 8 = 1048568 + 0 by decide]
    iexact Hptrslot
  iapply Wasm.SmallStep.twp_load32 ptr
    (by decide) (by decide) (by decide) (by decide) $$ Hptrslot'
  iintro _Hptrslot
  iapply Wasm.SmallStep.twp_localGet rfl
  iapply Wasm.SmallStep.twp_localGet rfl
  -- `call 0`: the search loop proper.
  iapply Wasm.SmallStep.twp_call «module» 0 func0Def
    (by simp [«module»]) (by simp [«module»]) $$ Hruntime
  iintro Hruntime
  simp [func0Def, Function.toLocals, Function.numParams, ValueType.zero]
  simp only [func0_eq, List.cons_append, List.nil_append]
  -- `func0` prologue: carve its frame at 1048544.
  iapply Wasm.SmallStep.twp_globalGet $$ HSP
  iintro HSP
  iapply Wasm.SmallStep.twp_const
  iapply Wasm.SmallStep.twp_sub
  rw [show (1048560 : UInt32) - 16 = 1048544 by decide]
  iapply Wasm.SmallStep.twp_localSet rfl
  simp only [List.length_cons, List.length_nil, Nat.reduceAdd,
    Nat.reduceSub, List.set]
  iapply Wasm.SmallStep.twp_localGet rfl
  iapply Wasm.SmallStep.twp_globalSet $$ HSP
  iintro HSP
  -- `lo := 0`
  iapply Wasm.SmallStep.twp_localGet rfl
  iapply Wasm.SmallStep.twp_const
  ihave Hlo' : pointsTo_u32 0 ((1048544 : UInt32) + 8) 0 $$ [Hlo]
  · rw [show (1048544 : UInt32) + 8 = 1048552 by decide]
    iexact Hlo
  iapply Wasm.SmallStep.twp_store32 0
    (by decide) (by decide) (by decide) (by decide) $$ Hlo'
  iintro Hlo
  -- `hi := len`
  iapply Wasm.SmallStep.twp_localGet rfl
  iapply Wasm.SmallStep.twp_localGet rfl
  ihave Hhi' : pointsTo_u32 0 ((1048544 : UInt32) + 12) 0 $$ [Hhi]
  · rw [show (1048544 : UInt32) + 12 = 1048556 by decide]
    iexact Hhi
  iapply Wasm.SmallStep.twp_store32 0
    (by decide) (by decide) (by decide) (by decide) $$ Hhi'
  iintro Hhi
  -- The result slot, in the address shape the loop uses.
  ihave Hres' : pointsTo_u32 0 ((1048544 : UInt32) + 4) 0 $$ [Hres]
  · rw [show (1048544 : UInt32) + 4 = 1048548 by decide]
    iexact Hres
  -- The outer block, then the memory-spilled loop.
  iapply Wasm.SmallStep.twp_block
  simp only [List.drop_zero]
  let Inv : SearchState → IProp (WasmHeapGF Unit) := fun st => iprop%
    ⌜st.lo ≤ st.hi ∧ st.hi ≤ arr.length ∧
      searchAux arr target st.lo st.hi
        = searchAux arr target 0 arr.length⌝ ∗
    arrayAt 0 ptr arr ∗
    pointsTo_u32 0 ((1048544 : UInt32) + 4) 0 ∗
    pointsTo_u32 0 ((1048544 : UInt32) + 8) (UInt32.ofNat st.lo) ∗
    pointsTo_u32 0 ((1048544 : UInt32) + 12) (UInt32.ofNat st.hi) ∗
    globalPointsToAt 0 0 (.i32 1048544) ∗
    runtimeModuleOwn ⟨0⟩ «module»
  iapply Wasm.SmallStep.twp_loop_wf_family
    (measure := fun st : SearchState => st.hi - st.lo)
    (locals := fun st => searchLocals0 ptr (UInt32.ofNat arr.length)
      target st.midv)
    (I := Inv)
    (initial := ⟨0, arr.length, 0⟩)
    (initialLocals := ⟨[.i32 ptr, .i32 (UInt32.ofNat arr.length),
        .i32 target],
      [.i32 1048544, .i32 0, .i32 0], []⟩)
    (belowStack := []) (hinitial := by rfl) (hbelow := by rfl)
  · -- One loop iteration.
    intro st
    simp only [Inv, Wasm.SmallStep.loopBodyExpr, loopBody, searchLocals0]
    iintro Hrec Hinv
    icases Hinv with ⟨%hstate, Harray, Hres, Hlo, Hhi, HSP, Hruntime⟩
    obtain ⟨hle, hhi_le, hwindow⟩ := hstate
    -- The top test: load `lo` and `hi`, compare.
    iapply Wasm.SmallStep.twp_block
    simp only [testBody, List.drop_zero]
    iapply Wasm.SmallStep.twp_localGet rfl
    iapply Wasm.SmallStep.twp_load32 (UInt32.ofNat st.lo)
      (by decide) (by decide) (by decide) (by decide) $$ Hlo
    iintro Hlo
    iapply Wasm.SmallStep.twp_localGet rfl
    iapply Wasm.SmallStep.twp_load32 (UInt32.ofNat st.hi)
      (by decide) (by decide) (by decide) (by decide) $$ Hhi
    iintro Hhi
    by_cases hlt0 : st.lo < st.hi
    · -- The window is nonempty: branch over the miss exit and iterate.
      iapply Wasm.SmallStep.twp_ltU (result := 1)
        (by rw [if_pos ((nat_lt_u32_iff (by omega) (by omega)).mpr hlt0)])
      iapply Wasm.SmallStep.twp_const
      iapply Wasm.SmallStep.twp_and
      rw [and_one_one]
      iapply Wasm.SmallStep.twp_brIf (by decide) rfl
      have hmidlen : mid st.lo st.hi < arr.length :=
        Nat.lt_of_lt_of_le (mid_lt_hi hlt0) hhi_le
      have hget : arr[mid st.lo st.hi]? = some arr[mid st.lo st.hi] :=
        List.getElem?_eq_getElem hmidlen
      -- `mid := ((hi - lo) >>u 1) + lo`, spilled to local 4.
      iapply Wasm.SmallStep.twp_localGet rfl
      iapply Wasm.SmallStep.twp_load32 (UInt32.ofNat st.lo)
        (by decide) (by decide) (by decide) (by decide) $$ Hlo
      iintro Hlo
      iapply Wasm.SmallStep.twp_localGet rfl
      iapply Wasm.SmallStep.twp_load32 (UInt32.ofNat st.hi)
        (by decide) (by decide) (by decide) (by decide) $$ Hhi
      iintro Hhi
      iapply Wasm.SmallStep.twp_localGet rfl
      iapply Wasm.SmallStep.twp_load32 (UInt32.ofNat st.lo)
        (by decide) (by decide) (by decide) (by decide) $$ Hlo
      iintro Hlo
      iapply Wasm.SmallStep.twp_sub
      iapply Wasm.SmallStep.twp_const
      iapply Wasm.SmallStep.twp_shrU
      iapply Wasm.SmallStep.twp_add
      rw [mid32_eq' (Nat.le_of_lt hlt0) (by omega)]
      iapply Wasm.SmallStep.twp_localSet rfl
      simp only [List.length_cons, List.length_nil, Nat.reduceAdd,
        Nat.reduceSub, List.set]
      -- Descend into the comparison blocks.
      iapply Wasm.SmallStep.twp_block
      simp only [b1Body, List.drop_zero]
      iapply Wasm.SmallStep.twp_block
      simp only [b2Body, List.drop_zero]
      iapply Wasm.SmallStep.twp_block
      simp only [b3Body, List.drop_zero]
      iapply Wasm.SmallStep.twp_block
      simp only [b4Body, List.drop_zero]
      iapply Wasm.SmallStep.twp_block
      simp only [b5Body, List.drop_zero]
      iapply Wasm.SmallStep.twp_block
      simp only [b6Body, List.drop_zero]
      iapply Wasm.SmallStep.twp_block
      simp only [b7Body, List.drop_zero]
      -- The bounds check `mid < len` holds, so the panic edge is dead.
      iapply Wasm.SmallStep.twp_localGet rfl
      iapply Wasm.SmallStep.twp_localGet rfl
      iapply Wasm.SmallStep.twp_ltU (result := 1)
        (by rw [if_pos ((nat_lt_u32_iff (by omega) (by omega)).mpr hmidlen)])
      iapply Wasm.SmallStep.twp_const
      iapply Wasm.SmallStep.twp_and
      rw [and_one_one]
      iapply Wasm.SmallStep.twp_eqz (result := 0) (by decide)
      iapply Wasm.SmallStep.twp_brIfZero
      -- Load `arr[mid]`.
      iapply Wasm.SmallStep.twp_localGet rfl
      iapply Wasm.SmallStep.twp_localGet rfl
      iapply Wasm.SmallStep.twp_const
      iapply Wasm.SmallStep.twp_shl
      iapply Wasm.SmallStep.twp_add
      rw [shl2_add_ptr]
      iapply twp_load32_cell ptr arr (mid st.lo st.hi) hmidlen hfit
      isplitl [Harray]
      · iexact Harray
      iintro Harray
      iapply Wasm.SmallStep.twp_localGet rfl
      by_cases hltT : arr[mid st.lo st.hi] < target
      · -- `arr[mid] < target`: go right, `lo := mid + 1`, back edge `br 4`.
        iapply Wasm.SmallStep.twp_ltU (result := 1) (by rw [if_pos hltT])
        iapply Wasm.SmallStep.twp_const
        iapply Wasm.SmallStep.twp_and
        rw [and_one_one]
        iapply Wasm.SmallStep.twp_brIf (by decide) rfl
        iapply Wasm.SmallStep.twp_localGet rfl
        iapply Wasm.SmallStep.twp_localGet rfl
        iapply Wasm.SmallStep.twp_const
        iapply Wasm.SmallStep.twp_add
        rw [one_add_ofNat]
        iapply Wasm.SmallStep.twp_store32 (UInt32.ofNat st.lo)
          (by decide) (by decide) (by decide) (by decide) $$ Hlo
        iintro Hlo
        iapply Wasm.SmallStep.twp_br rfl
        simp only [List.take_nil, List.append_nil]
        ispecialize Hrec $$ %(⟨mid st.lo st.hi + 1, st.hi,
          UInt32.ofNat (mid st.lo st.hi)⟩ : SearchState)
        isimp only [] at Hrec
        iapply Hrec
        · ipureintro
          show st.hi - (mid st.lo st.hi + 1) < st.hi - st.lo
          have := lo_le_mid st.lo st.hi
          omega
        isplitr
        · ipureintro
          exact ⟨mid_lt_hi hlt0, hhi_le,
            (searchAux_step_right hlt0 hget hltT).symm.trans hwindow⟩
        isplitl [Harray]
        · iexact Harray
        isplitl [Hres]
        · iexact Hres
        isplitl [Hlo]
        · iexact Hlo
        isplitl [Hhi]
        · iexact Hhi
        isplitl [HSP]
        · iexact HSP
        iexact Hruntime
      · -- `arr[mid] ≥ target`: the compiler re-tests the bound, then `>`.
        iapply Wasm.SmallStep.twp_ltU (result := 0) (by rw [if_neg hltT])
        iapply Wasm.SmallStep.twp_const
        iapply Wasm.SmallStep.twp_and
        rw [and_one_zero]
        iapply Wasm.SmallStep.twp_brIfZero
        iapply Wasm.SmallStep.twp_br rfl
        iapply Wasm.SmallStep.twp_localGet rfl
        iapply Wasm.SmallStep.twp_localGet rfl
        iapply Wasm.SmallStep.twp_ltU (result := 1)
          (by rw [if_pos ((nat_lt_u32_iff (by omega) (by omega)).mpr hmidlen)])
        iapply Wasm.SmallStep.twp_const
        iapply Wasm.SmallStep.twp_and
        rw [and_one_one]
        iapply Wasm.SmallStep.twp_brIf (by decide) rfl
        -- Reload `arr[mid]` and compare `>`.
        iapply Wasm.SmallStep.twp_localGet rfl
        iapply Wasm.SmallStep.twp_localGet rfl
        iapply Wasm.SmallStep.twp_const
        iapply Wasm.SmallStep.twp_shl
        iapply Wasm.SmallStep.twp_add
        rw [shl2_add_ptr]
        iapply twp_load32_cell ptr arr (mid st.lo st.hi) hmidlen hfit
        isplitl [Harray]
        · iexact Harray
        iintro Harray
        iapply Wasm.SmallStep.twp_localGet rfl
        by_cases hgtT : arr[mid st.lo st.hi] > target
        · -- Go left: `hi := mid`, back edge `br 0`.
          iapply Wasm.SmallStep.twp_gtU (result := 1) (by rw [if_pos hgtT])
          iapply Wasm.SmallStep.twp_const
          iapply Wasm.SmallStep.twp_and
          rw [and_one_one]
          iapply Wasm.SmallStep.twp_brIf (by decide) rfl
          iapply Wasm.SmallStep.twp_localGet rfl
          iapply Wasm.SmallStep.twp_localGet rfl
          iapply Wasm.SmallStep.twp_store32 (UInt32.ofNat st.hi)
            (by decide) (by decide) (by decide) (by decide) $$ Hhi
          iintro Hhi
          iapply Wasm.SmallStep.twp_br rfl
          simp only [List.take_nil, List.append_nil]
          ispecialize Hrec $$ %(⟨st.lo, mid st.lo st.hi,
            UInt32.ofNat (mid st.lo st.hi)⟩ : SearchState)
          isimp only [] at Hrec
          iapply Hrec
          · ipureintro
            show mid st.lo st.hi - st.lo < st.hi - st.lo
            have := mid_lt_hi hlt0
            omega
          isplitr
          · ipureintro
            exact ⟨lo_le_mid st.lo st.hi,
              Nat.le_trans (Nat.le_of_lt (mid_lt_hi hlt0)) hhi_le,
              (searchAux_step_left hlt0 hget hltT hgtT).symm.trans hwindow⟩
          isplitl [Harray]
          · iexact Harray
          isplitl [Hres]
          · iexact Hres
          isplitl [Hlo]
          · iexact Hlo
          isplitl [Hhi]
          · iexact Hhi
          isplitl [HSP]
          · iexact HSP
          iexact Hruntime
        · -- A hit: store `mid` in the result slot, leave through `br 2`.
          iapply Wasm.SmallStep.twp_gtU (result := 0) (by rw [if_neg hgtT])
          iapply Wasm.SmallStep.twp_const
          iapply Wasm.SmallStep.twp_and
          rw [and_one_zero]
          iapply Wasm.SmallStep.twp_brIfZero
          iapply Wasm.SmallStep.twp_br rfl
          iapply Wasm.SmallStep.twp_localGet rfl
          iapply Wasm.SmallStep.twp_localGet rfl
          iapply Wasm.SmallStep.twp_store32 0
            (by decide) (by decide) (by decide) (by decide) $$ Hres
          iintro Hres
          iapply Wasm.SmallStep.twp_br rfl
          simp only [List.take_nil, List.append_nil]
          have hhit : searchAux arr target 0 arr.length
              = some (mid st.lo st.hi) :=
            hwindow.symm.trans (searchAux_hit hlt0 hget hltT hgtT)
          iapply twp_searchExit ptr (UInt32.ofNat arr.length) target
            (UInt32.ofNat (mid st.lo st.hi))
            (UInt32.ofNat (mid st.lo st.hi)) arr
            ((searchResult_of_aux_some hhit).symm)
          isplitl [Hres]
          · iexact Hres
          isplitl [HSP]
          · iexact HSP
          iexact Hruntime
    · -- `lo ≥ hi`: store the miss sentinel and leave through `br 2`.
      iapply Wasm.SmallStep.twp_ltU (result := 0)
        (by rw [if_neg (fun h =>
          hlt0 ((nat_lt_u32_iff (by omega) (by omega)).mp h))])
      iapply Wasm.SmallStep.twp_const
      iapply Wasm.SmallStep.twp_and
      rw [and_one_zero]
      iapply Wasm.SmallStep.twp_brIfZero
      iapply Wasm.SmallStep.twp_localGet rfl
      iapply Wasm.SmallStep.twp_const
      iapply Wasm.SmallStep.twp_store32 0
        (by decide) (by decide) (by decide) (by decide) $$ Hres
      iintro Hres
      iapply Wasm.SmallStep.twp_br rfl
      simp only [List.take_nil, List.append_nil]
      have hmiss : searchAux arr target 0 arr.length = none := by
        rw [← hwindow]
        exact searchAux_none_of_ge (by omega)
      iapply twp_searchExit ptr (UInt32.ofNat arr.length) target
        4294967295 st.midv arr
        (by rw [searchResult_of_aux_none hmiss]; rfl)
      isplitl [Hres]
      · iexact Hres
      isplitl [HSP]
      · iexact HSP
      iexact Hruntime
  -- The invariant at entry: the untouched window `[0, len)`.
  simp only [Inv]
  isplitr
  · ipureintro
    exact ⟨Nat.zero_le _, Nat.le_refl _, trivial⟩
  isplitl [Harray]
  · iexact Harray
  isplitl [Hres']
  · iexact Hres'
  isplitl [Hlo]
  · rw [show UInt32.ofNat 0 = 0 from rfl]
    iexact Hlo
  isplitl [Hhi]
  · iexact Hhi
  isplitl [HSP]
  · iexact HSP
  iexact Hruntime

end WasmProof

/-! ## Adequacy: from the symbolic run to `TerminatesWith` -/

/-- The ghost global map: the stack pointer alone, at its initial value. -/
def searchGlobals : WasmGlobalMap Value :=
  PartialMap.singleton ⟨0, 0⟩ (.i32 1048576)

/-- The singleton global map agrees with the module's instantiated
globals: index 0 is `$__stack_pointer` at 1048576, and the map owns no
other index. -/
theorem searchGlobals_agrees :
    globalHeapAgrees searchGlobals
      ((«module».initialStore : Store Unit)).globals := by
  intro index value hget
  by_cases h : index = 0
  · subst h
    rw [searchGlobals, PartialMap.singleton, get?_insert_eq rfl] at hget
    injection hget with hvalue
    subst hvalue
    exact initial_global0
  · have hne : (⟨0, 0⟩ : GlobalKey) ≠ (⟨0, index⟩ : GlobalKey) := by
      intro hkey
      exact h ((congrArg GlobalKey.index hkey).symm)
    rw [searchGlobals, PartialMap.singleton, get?_insert_ne hne,
      get?_empty] at hget
    cases hget

/-- Total functional correctness of the compiled unoptimized artifact:
the export terminates on every array in the heap region and returns exactly
the pure model's answer. This discharges `BinarySearchSpec` verbatim. -/
@[proves BinarySearchSpec]
theorem binarySearchSpec_holds : BinarySearchSpec := by
  intro ptr arr target hbase hfit
  have hres : storeResolve (symbolicConfig ptr arr target).store =
      (fun id => if id = 0 then
        some (writeWords ((«module».initialStore : Store Unit)).mem ptr arr)
      else none) := by
    funext i
    by_cases h : i = 0
    · simp [storeResolve, symbolicConfig, h]
    · simp [storeResolve, symbolicConfig, h, initial_extraMems]
  exact wasm_smallStep_heap_globals_runtime_store_terminates
    (symbolicConfig ptr arr target) (searchHeap ptr arr) searchGlobals
    (fun values _ => values = [.i32 (searchResult arr target)])
    (by rw [hres]
        exact searchHeap_agrees ptr arr (by rw [usize_eq]; omega))
    (by rw [hres]
        exact searchHeap_inBounds ptr arr
          (by rw [usize_eq]; omega)
          (by rw [initial_mem_pages]; exact hfit))
    searchGlobals_agrees
    Nat.zero_lt_one
    (fun hlc gs => by
      letI := gs
      simp only [searchGlobals, BI.BigSepM.bigSepM_singleton.to_eq]
      exact twp_searchCall ptr arr target hbase hfit)

/-- Postcondition weakening for the corollaries: `TerminatesWith` is an
existential over traces, so a pointwise implication lifts through it. -/
private theorem terminatesWith_mono {config : Wasm.SmallStep.Config Unit}
    {P Q : List Value → MachineStore Unit → Prop}
    (h : Wasm.SmallStep.TerminatesWith config P)
    (himp : ∀ values store, P values store → Q values store) :
    Wasm.SmallStep.TerminatesWith config Q := by
  obtain ⟨trace, values, store, hsteps, hpost⟩ := h
  exact ⟨trace, values, store, hsteps, himp values store hpost⟩

/-- The layout bound keeps the array length far below `2 ^ 31`, which is
what the pure model's interpretation lemmas ask for. -/
private theorem length_small {ptr : UInt32} {arr : List UInt32}
    (hfit : ptr.toNat + 4 * arr.length ≤ 17 * 65536) :
    arr.length < 2 ^ 31 := by omega

/-! ## Determinism: from "some run returns the answer" to "every run does"

`TerminatesWith` is an existential over traces, so on its own it says that
*a* terminating run of the export reaches the model's answer. The Talos
semantics is deterministic (`step_deterministic`), and that is what turns the
existential into the universal reading: every run that terminates returns the
same value, and no run traps. The two corollaries below say so explicitly
rather than leaving the step to the reader.
-/

/-- Every run of the export that terminates normally returns exactly the pure
model's answer. Together with `binarySearchSpec_holds`, which supplies a
terminating run, this is the universal form of total correctness. -/
theorem binarySearch_result_unique (ptr : UInt32) (arr : List UInt32)
    (target : UInt32)
    (hbase : heapBase ≤ ptr)
    (hfit : ptr.toNat + 4 * arr.length ≤ 17 * 65536)
    {trace : List Wasm.SmallStep.StepKind} {values : List Value}
    {store : MachineStore Unit}
    (hrun : Wasm.SmallStep.Steps (symbolicConfig ptr arr target) trace
      ⟨.done values, store⟩) :
    values = [.i32 (searchResult arr target)] := by
  obtain ⟨_, _, _, hsteps, hpost⟩ :=
    binarySearchSpec_holds ptr arr target hbase hfit
  obtain ⟨rfl, rfl⟩ := Wasm.SmallStep.steps_done_deterministic hrun hsteps
  exact hpost

/-- The export never traps: the two compiled bounds checks, the panic calls
and the `unreachable` instructions behind them are all out of reach for any
array laid out in the heap region. -/
theorem binarySearch_never_traps (ptr : UInt32) (arr : List UInt32)
    (target : UInt32)
    (hbase : heapBase ≤ ptr)
    (hfit : ptr.toNat + 4 * arr.length ≤ 17 * 65536)
    {trace : List Wasm.SmallStep.StepKind} {reason : TrapReason}
    {store : MachineStore Unit}
    (hrun : Wasm.SmallStep.Steps (symbolicConfig ptr arr target) trace
      ⟨.trapped reason, store⟩) :
    False := by
  obtain ⟨_, _, _, hsteps, _⟩ :=
    binarySearchSpec_holds ptr arr target hbase hfit
  exact Wasm.SmallStep.steps_done_ne_trapped hsteps hrun

/-- Interpretation of a non-sentinel answer: the returned value is an index
into the array and the array holds the target there. No sortedness is
needed for this direction. -/
theorem terminates_hit (ptr : UInt32) (arr : List UInt32) (target : UInt32)
    (hbase : heapBase ≤ ptr)
    (hfit : ptr.toNat + 4 * arr.length ≤ 17 * 65536) :
    Wasm.SmallStep.TerminatesWith (symbolicConfig ptr arr target)
      (fun values _ => ∃ result : UInt32,
        values = [.i32 result] ∧
        (result ≠ notFound →
          result.toNat < arr.length ∧ arr[result.toNat]! = target)) := by
  apply terminatesWith_mono (binarySearchSpec_holds ptr arr target hbase hfit)
  intro values store hvalues
  exact ⟨searchResult arr target, hvalues,
    fun hne => searchResult_hit hne (length_small hfit)⟩

/-- Interpretation of the sentinel: for sorted input, `notFound` means the
target occurs nowhere in the array. Sortedness is exactly what licenses the
halving to discard half the window, so it appears here and nowhere else. -/
theorem terminates_miss (ptr : UInt32) (arr : List UInt32) (target : UInt32)
    (hsorted : Sorted arr)
    (hbase : heapBase ≤ ptr)
    (hfit : ptr.toNat + 4 * arr.length ≤ 17 * 65536) :
    Wasm.SmallStep.TerminatesWith (symbolicConfig ptr arr target)
      (fun values _ => ∃ result : UInt32,
        values = [.i32 result] ∧
        (result = notFound →
          ∀ k, k < arr.length → arr[k]! ≠ target)) := by
  apply terminatesWith_mono (binarySearchSpec_holds ptr arr target hbase hfit)
  intro values store hvalues
  exact ⟨searchResult arr target, hvalues,
    fun heq => searchResult_miss hsorted heq (length_small hfit)⟩

end Project.BinarySearch.TotalProof
