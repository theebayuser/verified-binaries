import Project.BinarySearchOpt3.Spec
import Project.BinarySearch.Rules

/-!
# Symbolic total correctness of the optimized artifact

Proves `BinarySearchOpt3Spec` from `Spec.lean`: for every array laid out in
the heap region and every target, the decoded export terminates and returns
exactly what the pure model returns.

Structure, bottom up:

1. Heap construction: `searchHeap ptr arr` is the ghost byte map covering the
   array cells, with agreement (`heapAgreesWithMem`), bounds
   (`heapAddressesInBounds`) and ownership (`bigSepM ... ⊢ arrayAt ptr arr`)
   lemmas connecting it to the physical `writeWords` memory of the entry
   configuration. Mirrors the u64 stream construction of the upstream
   selection-sort StdIO proof, with 4-byte cells instead of 8.
2. Pure-model window lemmas and `UInt32` arithmetic bridges.
3. A total-WP loop proof over the compiled body, measure `hi - lo`.
4. Adequacy, discharging the fuel-free `TerminatesWith` statement.
-/

namespace Project.BinarySearchOpt3.TotalProof

open Wasm Wasm.SepLogic Wasm.SmallStep
open Iris Iris.Std
open Project.BinarySearch.Pure
open Project.BinarySearchOpt3.Spec

/-! ## Pages are untouched by the entry configuration's writes -/

theorem write32_pages (m : Mem) (a v : UInt32) :
    (m.write32 a v).pages = m.pages := rfl

theorem writeWords_pages (m : Mem) (base : UInt32) (vs : List UInt32) :
    (writeWords m base vs).pages = m.pages := by
  induction vs generalizing m base with
  | nil => rfl
  | cons v vs ih =>
      simp only [writeWords]
      rw [ih, write32_pages]

set_option maxRecDepth 40000 in
/-- The module allocates 17 pages of linear memory. The raised recursion
depth only lets `rfl` walk the module's 1217-byte data segment; no axioms
are involved. -/
theorem initial_mem_pages :
    ((«module».initialStore : Store Unit)).mem.pages = 17 := rfl

/-! ## The ghost byte map for the array region

`searchHeap ptr arr` owns exactly the bytes of the `arr.length` consecutive
u32 cells starting at `ptr`, with the little-endian bytes of each element.
-/

/-- Fold `store32Heap` over the array, 4 bytes per element. -/
def heap32Aux (heap : WasmHeapMap (Option UInt8)) (base : UInt32) :
    List UInt32 → WasmHeapMap (Option UInt8)
  | [] => heap
  | value :: values => heap32Aux (store32Heap heap base value) (base + 4) values

/-- The ghost heap covering the array cells of the entry configuration. -/
def searchHeap (ptr : UInt32) (arr : List UInt32) :
    WasmHeapMap (Option UInt8) :=
  heap32Aux ∅ ptr arr

theorem heap32Aux_agrees
    (heap : WasmHeapMap (Option UInt8)) (mem : Mem) (base : UInt32)
    (values : List UInt32) (hagree : heapAgreesWithMem heap mem)
    (hfit : base.toNat + 4 * values.length < UInt32.size) :
    heapAgreesWithMem (heap32Aux heap base values)
      (writeWords mem base values) := by
  induction values generalizing heap mem base with
  | nil => simpa [heap32Aux, writeWords]
  | cons value values ih =>
      simp only [heap32Aux, writeWords, List.length_cons] at *
      simp only [UInt32.size] at hfit
      apply ih
      · apply store32_sound
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
    (values : List UInt32) (hinBounds : heapAddressesInBounds heap mem)
    (hfit : base.toNat + 4 * values.length < UInt32.size)
    (hmem : base.toNat + 4 * values.length ≤ mem.pages * 65536) :
    heapAddressesInBounds (heap32Aux heap base values)
      (writeWords mem base values) := by
  induction values generalizing heap mem base with
  | nil => simpa [heap32Aux, writeWords]
  | cons value values ih =>
      simp only [heap32Aux, writeWords, List.length_cons] at *
      simp only [UInt32.size] at hfit
      have h4 : (base + 4 : UInt32).toNat = base.toNat + 4 :=
        UInt32.add_ofNat_toNat_noWrap base 4 (by decide) (by omega)
      apply ih
      · apply store32_inBounds
        · exact UInt32.add_ofNat_toNat_noWrap base 1 (by decide) (by omega)
        · exact UInt32.add_ofNat_toNat_noWrap base 2 (by decide) (by omega)
        · exact UInt32.add_ofNat_toNat_noWrap base 3 (by decide) (by omega)
        · exact hinBounds
        · omega
      · rw [h4]
        simp only [UInt32.size]
        omega
      · rw [write32_pages, h4]
        omega

set_option maxHeartbeats 2000000 in
theorem heap32Aux_pointsTo [WasmHeapGS Unit]
    (heap : WasmHeapMap (Option UInt8)) (base : UInt32)
    (values : List UInt32)
    (hdisjoint : ∀ address byte, get? heap address = some byte →
      address.toNat < base.toNat)
    (hfit : base.toNat + 4 * values.length < UInt32.size) :
    ([∗map] address ↦ value ∈ heap32Aux heap base values,
      pointsTo (GF := WasmHeapGF Unit) (H := WasmHeapMap)
        address (DFrac.own 1) value) ⊢
      arrayAt base values ∗
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
          get? heap (base + UInt32.ofNat n) = none := by
        by_contra h
        obtain ⟨byte, hbyte⟩ := Option.ne_none_iff_exists.mp h
        have hlt := hdisjoint _ _ hbyte.symm
        rw [hn n (by omega)] at hlt
        omega
      have hget0 : get? heap base = none := by
        simpa using hget 0 (by omega)
      have hgetL1 : get? heap (base + 1) = none := by
        simpa using hget 1 (by omega)
      have hgetL2 : get? heap (base + 2) = none := by
        simpa using hget 2 (by omega)
      have hgetL3 : get? heap (base + 3) = none := by
        simpa using hget 3 (by omega)
      have hdisjoint' : ∀ address byte,
          get? (store32Heap heap base value) address = some byte →
          address.toNat < (base + 4).toNat := by
        intro address byte haddress
        change address.toNat < (base + UInt32.ofNat 4).toNat
        rw [hn4]
        by_cases h3 : address = base + 3
        · subst address; rw [hl3]; omega
        by_cases h2 : address = base + 2
        · subst address; rw [hl2]; omega
        by_cases h1 : address = base + 1
        · subst address; rw [hl1]; omega
        by_cases h0 : address = base
        · subst address; omega
        simp only [store32Heap, get?_insert_ne (Ne.symm h3),
          get?_insert_ne (Ne.symm h2), get?_insert_ne (Ne.symm h1),
          get?_insert_ne (Ne.symm h0)] at haddress
        have hlt := hdisjoint address byte haddress
        omega
      have hfit' : (base + 4).toNat + 4 * values.length < UInt32.size := by
        change (base + UInt32.ofNat 4).toNat + 4 * values.length < UInt32.size
        rw [hn4]
        simp only [UInt32.size]
        omega
      iintro Hheap
      ihave Hsplit := ih (store32Heap heap base value) (base + 4)
        hdisjoint' hfit' $$ Hheap
      icases Hsplit with ⟨Hvalues, Hstored⟩
      ihave Hword := store32Heap_pointsTo heap base value
        hget0 hgetL1 hgetL2 hgetL3 hl1 hl2 hl3 $$ Hstored
      icases Hword with ⟨Hword, Hheap⟩
      simp only [arrayAt]
      isplitl [Hword Hvalues]
      · isplitl [Hword]
        · iexact Hword
        · iexact Hvalues
      · iexact Hheap

/-! ## The three faces of `searchHeap` at the entry configuration -/

theorem searchHeap_agrees (mem : Mem) (ptr : UInt32) (arr : List UInt32)
    (hfit : ptr.toNat + 4 * arr.length < UInt32.size) :
    heapAgreesWithMem (searchHeap ptr arr) (writeWords mem ptr arr) :=
  heap32Aux_agrees ∅ mem ptr arr (heapAgreesWithMem_empty mem) hfit

theorem searchHeap_inBounds (mem : Mem) (ptr : UInt32) (arr : List UInt32)
    (hfit : ptr.toNat + 4 * arr.length < UInt32.size)
    (hmem : ptr.toNat + 4 * arr.length ≤ mem.pages * 65536) :
    heapAddressesInBounds (searchHeap ptr arr) (writeWords mem ptr arr) :=
  heap32Aux_inBounds ∅ mem ptr arr (heapAddressesInBounds_empty mem) hfit hmem

theorem searchHeap_pointsTo [WasmHeapGS Unit]
    (ptr : UInt32) (arr : List UInt32)
    (hfit : ptr.toNat + 4 * arr.length < UInt32.size) :
    ([∗map] address ↦ value ∈ searchHeap ptr arr,
      pointsTo (GF := WasmHeapGF Unit) (H := WasmHeapMap)
        address (DFrac.own 1) value) ⊢ arrayAt ptr arr := by
  unfold searchHeap
  iintro Hheap
  ihave Hsplit := heap32Aux_pointsTo ∅ ptr arr
    (fun address byte hget => by simp [get?_empty] at hget)
    hfit $$ Hheap
  icases Hsplit with ⟨Harray, _Hempty⟩
  iexact Harray

/-! ## `UInt32` arithmetic bridges

Everything the loop proof needs to move between the machine's 32-bit
arithmetic and the pure model's `Nat` arithmetic. The `17 * 65536` layout
bound makes every quantity small enough that nothing wraps.
-/

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

/-- The compiled scaling `index <<u 2` is multiplication by the cell size. -/
private theorem shl2_eq_mul4 (index : UInt32) :
    index <<< ((2 : UInt32) % 32) = 4 * index := by
  apply UInt32.toNat_inj.mp
  rw [UInt32.toNat_shiftLeft, UInt32.toNat_mul,
    show ((2 : UInt32) % 32).toNat % 32 = 2 from rfl,
    Nat.shiftLeft_eq, show (4 : UInt32).toNat = 4 from rfl]
  omega

/-- The address the compiled code computes, in the shape `arrayAt` indexes
by: `(mid <<u 2) + ptr = ptr + 4 * mid`. -/
private theorem shl2_add_ptr (ptr index : UInt32) :
    index <<< ((2 : UInt32) % 32) + ptr = ptr + 4 * index := by
  rw [shl2_eq_mul4, UInt32.add_comm]

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

/-! ## The compiled control flow, named

The decoded body is three nested blocks around a bottom-tested loop, with
two more blocks inside the loop. Naming each body and each control frame
keeps the branch-target obligations readable; every equation here is `rfl`
against `Program.lean`, so the names cannot drift from the artifact.
-/

/-- The code after the outermost block: the panic call for the
`mid ≥ len` bounds check, which the proof shows is unreachable. -/
def panicTail : Program :=
  [.localGet 5, .localGet 1, .const (1048788 : UInt32), .call 52,
   .unreachable]

/-- Innermost block: load `arr[mid]` and compare three ways. -/
def bodyE : Program :=
  [.localGet 0, .localGet 5, .const (2 : UInt32), .shl, .add,
   .load32 (0 : UInt32), .localSet 6,
   .localGet 6, .localGet 2, .ltU, .br_if 0,
   .localGet 5, .localSet 4,
   .localGet 6, .localGet 2, .gtU, .br_if 1,
   .br 4]

/-- Block around the comparison: its continuation is the go-right update. -/
def bodyD : Program :=
  [.block 0 0 bodyE [] [],
   .localGet 5, .const (1 : UInt32), .add, .localSet 3]

/-- The loop body: compute `mid`, bounds-check it, compare, then the
bottom test `lo <u hi`. -/
def loopBody : Program :=
  [.localGet 4, .localGet 3, .sub, .const (1 : UInt32), .shrU,
   .localGet 3, .add, .localSet 5,
   .localGet 5, .localGet 1, .geU, .br_if 3,
   .block 0 0 bodyD [] [],
   .localGet 3, .localGet 4, .ltU, .br_if 0]

/-- Block C: the `len = 0` early exit and the loop. Falling out (or the
`br_if 0`) reaches the miss continuation. -/
def bodyC : Program :=
  [.localGet 1, .eqz, .br_if 0,
   .const (0 : UInt32), .localSet 3,
   .localGet 1, .localSet 4,
   .loop 0 0 loopBody [] []]

/-- Block B: its continuation stores the `-1` miss sentinel. -/
def bodyB : Program :=
  [.block 0 0 bodyC [] [],
   .const (4294967295 : UInt32), .localSet 5]

/-- Block A: its continuation returns local 5, where both the hit and the
miss path have left the result. -/
def bodyA : Program :=
  [.block 0 0 bodyB [] [],
   .localGet 5, .ret]

/-- The decomposition is definitional against the decoded artifact. -/
theorem func0_eq : func0 = .block 0 0 bodyA [] [] :: panicTail := rfl

/-- Frame pushed on entering block A. All frames in this function are
pushed with an empty operand stack, so every `belowStack` is `[]`. -/
def frameA : ControlFrame :=
  { kind := .block, paramArity := 0, resultArity := 0,
    body := bodyA, continuation := panicTail, belowStack := [] }

/-- Frame for block B; exits converge here to `localGet 5; ret`. -/
def frameB : ControlFrame :=
  { kind := .block, paramArity := 0, resultArity := 0,
    body := bodyB, continuation := [.localGet 5, .ret], belowStack := [] }

/-- Frame for block C; falling out stores the miss sentinel. -/
def frameC : ControlFrame :=
  { kind := .block, paramArity := 0, resultArity := 0,
    body := bodyC,
    continuation := [.const (4294967295 : UInt32), .localSet 5],
    belowStack := [] }

/-! ## The machine states of the loop -/

/-- Locals layout of `func0`: parameters `ptr`, `len`, `target`; scratch
locals `lo`, `hi`, `mid` (also the result), `elem`. -/
def searchLocals (ptr len32 target lo hi midv elemv : UInt32) : Locals :=
  ⟨[.i32 ptr, .i32 len32, .i32 target],
   [.i32 lo, .i32 hi, .i32 midv, .i32 elemv], []⟩

/-- The changing data of one loop iteration: the pure window plus the two
scratch locals, which carry stale values into the next iteration. -/
structure SearchState where
  lo : Nat
  hi : Nat
  midv : UInt32
  elemv : UInt32

/-! ## The focused load rule -/

section WasmProof

open Iris.ProgramLogic Language.Notation

variable [WasmSmallStepGS hlc Unit]
local instance instBinarySearchOpt3TotalIrisGS :
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
    arrayAt ptr xs ∗
      (arrayAt ptr xs -∗
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
  ihave Hcell := arrayAt_get ptr xs k hk $$ Harray
  icases Hcell with ⟨Hword, Hrestore⟩
  ihave Hword' : pointsTo_u32 (ptr + 4 * UInt32.ofNat k + 0) xs[k] $$ [Hword]
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

/-! ## The whole export, in one total weakest precondition -/

set_option maxHeartbeats 8000000 in
/-- Total WP for the export against the pure model, in exactly the
postcondition shape the adequacy theorem consumes. The `runtimeModuleOwn`
resource is taken and dropped: the proven path never executes `call`. -/
theorem twp_searchCall
    (ptr : UInt32) (arr : List UInt32) (target : UInt32)
    (hfit : ptr.toNat + 4 * arr.length ≤ 17 * 65536) :
    (([∗map] address ↦ value ∈ searchHeap ptr arr,
        pointsTo (GF := WasmHeapGF Unit) (H := WasmHeapMap)
          address (DFrac.own 1) value) ∗
      runtimeModuleOwn (symbolicConfig ptr arr target).store.runtime.module) ⊢
      WP (symbolicConfig ptr arr target).expr @ Stuckness.NotStuck; ⊤
        [{ values,
          ∀ (store : MachineStore Unit) (_observations : List StepKind),
            stateInterp (GF := WasmHeapGF Unit) store 0 [] 0 -∗
            ⌜values = [.i32 (searchResult arr target)]⌝ }] := by
  iintro ⟨Hheap, _Hruntime⟩
  ihave Harray := searchHeap_pointsTo ptr arr (by rw [usize_eq]; omega) $$ Hheap
  simp only [symbolicConfig, func0_eq]
  iapply Wasm.SmallStep.twp_block
  simp only [bodyA]
  iapply Wasm.SmallStep.twp_block
  simp only [bodyB]
  iapply Wasm.SmallStep.twp_block
  simp only [bodyC, List.drop_zero]
  iapply Wasm.SmallStep.twp_localGet rfl
  by_cases hzero : arr.length = 0
  · -- Empty array: the `eqz` early exit, straight to the miss sentinel.
    iapply Wasm.SmallStep.twp_eqz (result := 1) (by simp [hzero])
    iapply Wasm.SmallStep.twp_brIf (by decide) rfl
    iapply Wasm.SmallStep.twp_const
    iapply Wasm.SmallStep.twp_localSet rfl
    iapply Wasm.SmallStep.twp_exitControl (by rfl)
    iapply Wasm.SmallStep.twp_localGet rfl
    iapply Wasm.SmallStep.twp_returnFromFunction
    iapply twp.value rfl
    iintro %store %observations _Hstate
    ipureintro
    have hmiss : searchResult arr target = notFound :=
      searchResult_of_aux_none (searchAux_none_of_ge (by omega))
    rw [hmiss]
    rfl
  · -- Nonempty array: initialize `lo := 0`, `hi := len`, enter the loop.
    have hlen32 : UInt32.ofNat arr.length ≠ 0 := by
      intro h
      have h' := congrArg UInt32.toNat h
      rw [UInt32.toNat_ofNat_of_lt' (by rw [usize_eq]; omega)] at h'
      exact hzero h'
    iapply Wasm.SmallStep.twp_eqz (result := 0) (by rw [if_neg hlen32])
    iapply Wasm.SmallStep.twp_brIfZero
    iapply Wasm.SmallStep.twp_const
    iapply Wasm.SmallStep.twp_localSet rfl
    iapply Wasm.SmallStep.twp_localGet rfl
    iapply Wasm.SmallStep.twp_localSet rfl
    -- Renormalize the interpreter's `List.set` bookkeeping into a literal.
    simp only [List.length_cons, List.length_nil, Nat.reduceAdd,
      Nat.reduceSub, List.set]
    let Inv : SearchState → IProp (WasmHeapGF Unit) := fun st => iprop%
      ⌜st.lo < st.hi ∧ st.hi ≤ arr.length ∧
        searchAux arr target st.lo st.hi
          = searchAux arr target 0 arr.length⌝ ∗
      arrayAt ptr arr
    iapply Wasm.SmallStep.twp_loop_wf_family
      (measure := fun st : SearchState => st.hi - st.lo)
      (locals := fun st => searchLocals ptr (UInt32.ofNat arr.length) target
        (UInt32.ofNat st.lo) (UInt32.ofNat st.hi) st.midv st.elemv)
      (I := Inv)
      (initial := ⟨0, arr.length, 0, 0⟩)
      (initialLocals := ⟨[.i32 ptr, .i32 (UInt32.ofNat arr.length), .i32 target],
        [.i32 0, .i32 (UInt32.ofNat arr.length), .i32 0, .i32 0], []⟩)
      (belowStack := []) (hinitial := by rfl) (hbelow := by rfl)
    · -- One loop iteration.
      intro st
      simp only [Inv, Wasm.SmallStep.loopBodyExpr, loopBody]
      iintro Hrec Hinv
      icases Hinv with ⟨%hstate, Harray⟩
      obtain ⟨hlo_lt, hhi_le, hwindow⟩ := hstate
      have hlenS : arr.length < UInt32.size := by rw [usize_eq]; omega
      have hmidlen : mid st.lo st.hi < arr.length :=
        Nat.lt_of_lt_of_le (mid_lt_hi hlo_lt) hhi_le
      have hget : arr[mid st.lo st.hi]? = some arr[mid st.lo st.hi] :=
        List.getElem?_eq_getElem hmidlen
      -- `mid := ((hi - lo) >>u 1) + lo`
      iapply Wasm.SmallStep.twp_localGet rfl
      iapply Wasm.SmallStep.twp_localGet rfl
      iapply Wasm.SmallStep.twp_sub
      iapply Wasm.SmallStep.twp_const
      iapply Wasm.SmallStep.twp_shrU
      iapply Wasm.SmallStep.twp_localGet rfl
      iapply Wasm.SmallStep.twp_add
      rw [mid32_eq (Nat.le_of_lt hlo_lt) (by omega)]
      iapply Wasm.SmallStep.twp_localSet rfl
      simp only [searchLocals, List.length_cons, List.length_nil,
        Nat.reduceAdd, Nat.reduceSub, List.set]
      -- The bounds check `mid >=u len` cannot fire: `mid < hi <= len`.
      iapply Wasm.SmallStep.twp_localGet rfl
      iapply Wasm.SmallStep.twp_localGet rfl
      iapply Wasm.SmallStep.twp_geU (result := 0)
        (by rw [if_neg (u32_not_le
          ((nat_lt_u32_iff (by omega) (by omega)).mpr hmidlen))])
      iapply Wasm.SmallStep.twp_brIfZero
      iapply Wasm.SmallStep.twp_block
      simp only [bodyD]
      iapply Wasm.SmallStep.twp_block
      simp only [bodyE]
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
      iapply Wasm.SmallStep.twp_localSet rfl
      simp only [List.length_cons, List.length_nil,
        Nat.reduceAdd, Nat.reduceSub, List.set]
      -- Compare with the target.
      iapply Wasm.SmallStep.twp_localGet rfl
      iapply Wasm.SmallStep.twp_localGet rfl
      by_cases hlt : arr[mid st.lo st.hi] < target
      · -- `arr[mid] < target`: go right, `lo := mid + 1`.
        iapply Wasm.SmallStep.twp_ltU (result := 1) (by rw [if_pos hlt])
        iapply Wasm.SmallStep.twp_brIf (by decide) rfl
        iapply Wasm.SmallStep.twp_localGet rfl
        iapply Wasm.SmallStep.twp_const
        iapply Wasm.SmallStep.twp_add
        rw [one_add_ofNat]
        iapply Wasm.SmallStep.twp_localSet rfl
        simp only [List.length_cons, List.length_nil,
          Nat.reduceAdd, Nat.reduceSub, List.set]
        iapply Wasm.SmallStep.twp_exitControl (by rfl)
        iapply Wasm.SmallStep.twp_localGet rfl
        iapply Wasm.SmallStep.twp_localGet rfl
        by_cases hcont : mid st.lo st.hi + 1 < st.hi
        · -- Back edge with the narrowed window `[mid+1, hi)`.
          iapply Wasm.SmallStep.twp_ltU (result := 1)
            (by rw [if_pos ((nat_lt_u32_iff (by omega) (by omega)).mpr hcont)])
          iapply Wasm.SmallStep.twp_brIf (by decide) rfl
          simp only [List.take_nil, List.drop_nil,
            List.append_nil]
          ispecialize Hrec $$ %(⟨mid st.lo st.hi + 1, st.hi,
            UInt32.ofNat (mid st.lo st.hi), arr[mid st.lo st.hi]⟩ : SearchState)
          isimp only [] at Hrec
          iapply Hrec
          · ipureintro
            show st.hi - (mid st.lo st.hi + 1) < st.hi - st.lo
            have := lo_le_mid st.lo st.hi
            omega
          isplitr
          · ipureintro
            exact ⟨hcont, hhi_le,
              (searchAux_step_right hlo_lt hget hlt).symm.trans hwindow⟩
          iexact Harray
        · -- Window emptied from the left: a miss.
          iapply Wasm.SmallStep.twp_ltU (result := 0)
            (by rw [if_neg (fun h =>
              hcont ((nat_lt_u32_iff (by omega) (by omega)).mp h))])
          iapply Wasm.SmallStep.twp_brIfZero
          iapply Wasm.SmallStep.twp_exitControl (by rfl)
          iapply Wasm.SmallStep.twp_exitControl (by rfl)
          iapply Wasm.SmallStep.twp_const
          iapply Wasm.SmallStep.twp_localSet rfl
          simp only [List.length_cons, List.length_nil,
            Nat.reduceAdd, Nat.reduceSub, List.set]
          iapply Wasm.SmallStep.twp_exitControl (by rfl)
          iapply Wasm.SmallStep.twp_localGet rfl
          iapply Wasm.SmallStep.twp_returnFromFunction
          iapply twp.value rfl
          iintro %store %observations _Hstate
          ipureintro
          have hmiss : searchAux arr target 0 arr.length = none := by
            rw [← hwindow, searchAux_step_right hlo_lt hget hlt]
            exact searchAux_none_of_ge (by omega)
          rw [searchResult_of_aux_none hmiss]
          rfl
      · -- `arr[mid] >= target`: first `hi := mid`, then test `>`.
        iapply Wasm.SmallStep.twp_ltU (result := 0) (by rw [if_neg hlt])
        iapply Wasm.SmallStep.twp_brIfZero
        iapply Wasm.SmallStep.twp_localGet rfl
        iapply Wasm.SmallStep.twp_localSet rfl
        simp only [List.length_cons, List.length_nil,
          Nat.reduceAdd, Nat.reduceSub, List.set]
        iapply Wasm.SmallStep.twp_localGet rfl
        iapply Wasm.SmallStep.twp_localGet rfl
        by_cases hgt : arr[mid st.lo st.hi] > target
        · -- `arr[mid] > target`: go left, window `[lo, mid)`.
          iapply Wasm.SmallStep.twp_gtU (result := 1) (by rw [if_pos hgt])
          iapply Wasm.SmallStep.twp_brIf (by decide) rfl
          iapply Wasm.SmallStep.twp_localGet rfl
          iapply Wasm.SmallStep.twp_localGet rfl
          by_cases hcont : st.lo < mid st.lo st.hi
          · -- Back edge with the narrowed window `[lo, mid)`.
            iapply Wasm.SmallStep.twp_ltU (result := 1)
              (by rw [if_pos ((nat_lt_u32_iff (by omega) (by omega)).mpr hcont)])
            iapply Wasm.SmallStep.twp_brIf (by decide) rfl
            simp only [List.take_nil, List.drop_nil,
              List.append_nil]
            ispecialize Hrec $$ %(⟨st.lo, mid st.lo st.hi,
              UInt32.ofNat (mid st.lo st.hi), arr[mid st.lo st.hi]⟩ : SearchState)
            isimp only [] at Hrec
            iapply Hrec
            · ipureintro
              show mid st.lo st.hi - st.lo < st.hi - st.lo
              have := mid_lt_hi hlo_lt
              omega
            isplitr
            · ipureintro
              exact ⟨hcont,
                Nat.le_trans (Nat.le_of_lt (mid_lt_hi hlo_lt)) hhi_le,
                (searchAux_step_left hlo_lt hget hlt hgt).symm.trans hwindow⟩
            iexact Harray
          · -- Window emptied from the right: a miss.
            iapply Wasm.SmallStep.twp_ltU (result := 0)
              (by rw [if_neg (fun h =>
                hcont ((nat_lt_u32_iff (by omega) (by omega)).mp h))])
            iapply Wasm.SmallStep.twp_brIfZero
            iapply Wasm.SmallStep.twp_exitControl (by rfl)
            iapply Wasm.SmallStep.twp_exitControl (by rfl)
            iapply Wasm.SmallStep.twp_const
            iapply Wasm.SmallStep.twp_localSet rfl
            simp only [List.length_cons, List.length_nil,
              Nat.reduceAdd, Nat.reduceSub, List.set]
            iapply Wasm.SmallStep.twp_exitControl (by rfl)
            iapply Wasm.SmallStep.twp_localGet rfl
            iapply Wasm.SmallStep.twp_returnFromFunction
            iapply twp.value rfl
            iintro %store %observations _Hstate
            ipureintro
            have hmiss : searchAux arr target 0 arr.length = none := by
              rw [← hwindow, searchAux_step_left hlo_lt hget hlt hgt]
              exact searchAux_none_of_ge (by omega)
            rw [searchResult_of_aux_none hmiss]
            rfl
        · -- `arr[mid] = target`: `br 4` straight to the return.
          iapply Wasm.SmallStep.twp_gtU (result := 0) (by rw [if_neg hgt])
          iapply Wasm.SmallStep.twp_brIfZero
          iapply Wasm.SmallStep.twp_br rfl
          iapply Wasm.SmallStep.twp_localGet rfl
          iapply Wasm.SmallStep.twp_returnFromFunction
          iapply twp.value rfl
          iintro %store %observations _Hstate
          ipureintro
          have hhit : searchAux arr target 0 arr.length
              = some (mid st.lo st.hi) :=
            hwindow.symm.trans (searchAux_hit hlo_lt hget hlt hgt)
          rw [searchResult_of_aux_some hhit]
          rfl
    -- The invariant holds at entry: `lo = 0 < len = hi`, window untouched.
    isplitr
    · ipureintro
      exact ⟨Nat.pos_of_ne_zero hzero, Nat.le_refl _, rfl⟩
    iexact Harray

end WasmProof

/-! ## Adequacy: from the total WP to the fuel-free statement -/

/-- Total functional correctness of the compiled opt-level 3 artifact:
the export terminates on every array in the heap region and returns exactly
the pure model's answer. This discharges `BinarySearchOpt3Spec` verbatim. -/
@[proves BinarySearchOpt3Spec]
theorem binarySearchOpt3Spec_holds : BinarySearchOpt3Spec := by
  intro ptr arr target _hbase hfit
  exact wasm_smallStep_heap_store_terminates.{0}
    (symbolicConfig ptr arr target) (searchHeap ptr arr)
    (fun values _ => values = [.i32 (searchResult arr target)])
    (searchHeap_agrees («module».initialStore : Store Unit).mem ptr arr
      (by rw [usize_eq]; omega))
    (searchHeap_inBounds («module».initialStore : Store Unit).mem ptr arr
      (by rw [usize_eq]; omega)
      (by rw [initial_mem_pages]; exact hfit))
    (fun hlc gs => twp_searchCall ptr arr target hfit)

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
model's answer. Together with `binarySearchOpt3Spec_holds`, which supplies a
terminating run, this is the universal form of total correctness. -/
theorem binarySearchOpt3_result_unique (ptr : UInt32) (arr : List UInt32)
    (target : UInt32)
    (hbase : heapBase ≤ ptr)
    (hfit : ptr.toNat + 4 * arr.length ≤ 17 * 65536)
    {trace : List Wasm.SmallStep.StepKind} {values : List Value}
    {store : MachineStore Unit}
    (hrun : Wasm.SmallStep.Steps (symbolicConfig ptr arr target) trace
      ⟨.done values, store⟩) :
    values = [.i32 (searchResult arr target)] := by
  obtain ⟨_, _, _, hsteps, hpost⟩ :=
    binarySearchOpt3Spec_holds ptr arr target hbase hfit
  obtain ⟨rfl, rfl⟩ := Wasm.SmallStep.steps_done_deterministic hrun hsteps
  exact hpost

/-- The export never traps: the compiled bounds check, the panic call and the
`unreachable` that follows it are all out of reach for any array laid out in
the heap region. -/
theorem binarySearchOpt3_never_traps (ptr : UInt32) (arr : List UInt32)
    (target : UInt32)
    (hbase : heapBase ≤ ptr)
    (hfit : ptr.toNat + 4 * arr.length ≤ 17 * 65536)
    {trace : List Wasm.SmallStep.StepKind} {reason : TrapReason}
    {store : MachineStore Unit}
    (hrun : Wasm.SmallStep.Steps (symbolicConfig ptr arr target) trace
      ⟨.trapped reason, store⟩) :
    False := by
  obtain ⟨_, _, _, hsteps, _⟩ :=
    binarySearchOpt3Spec_holds ptr arr target hbase hfit
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
  apply terminatesWith_mono (binarySearchOpt3Spec_holds ptr arr target hbase hfit)
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
  apply terminatesWith_mono (binarySearchOpt3Spec_holds ptr arr target hbase hfit)
  intro values store hvalues
  exact ⟨searchResult arr target, hvalues,
    fun heq => searchResult_miss hsorted heq (length_small hfit)⟩

end Project.BinarySearchOpt3.TotalProof
