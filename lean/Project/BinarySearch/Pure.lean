/-!
# Pure model for `binary_search`

The list-level model the compiled artifacts are proved against, with no Wasm
and no separation logic in sight. Keeping it separate means the specification
can be read and checked on its own terms, and the same model serves both the
opt-level 0 and the opt-level 3 proof.

`searchAux` recurses on `hi - lo`, the same quantity the compiled loops
decrease, so the Iris loop invariant and this definition stay in step.

This file deliberately depends on nothing: it typechecks against a bare Lean
toolchain, so the specification can be reviewed without building the
verification stack.
-/

namespace Project.BinarySearch.Pure

/-- Sorted in nondecreasing order. -/
def Sorted (xs : List UInt32) : Prop :=
  ∀ i j : Nat, i ≤ j → j < xs.length → xs[i]! ≤ xs[j]!

/-- The midpoint the compiled code computes: `lo + (hi - lo) / 2`, which
cannot overflow. At opt-level 3 this is emitted as `((hi - lo) >>u 1) + lo`. -/
def mid (lo hi : Nat) : Nat := lo + (hi - lo) / 2

theorem lo_le_mid (lo hi : Nat) : lo ≤ mid lo hi := by
  unfold mid; omega

theorem mid_lt_hi {lo hi : Nat} (h : lo < hi) : mid lo hi < hi := by
  unfold mid; omega

/-- Binary search over `xs[lo:hi]`, returning the index of an occurrence of
`target` when the halving finds one.

With duplicates this reports whichever occurrence the halving lands on, not
necessarily the leftmost, which is exactly what the compiled code does. -/
def searchAux (xs : List UInt32) (target : UInt32) (lo hi : Nat) : Option Nat :=
  if _hlt : lo < hi then
    match xs[mid lo hi]? with
    | none => none
    | some v =>
      if v < target then searchAux xs target (mid lo hi + 1) hi
      else if target < v then searchAux xs target lo (mid lo hi)
      else some (mid lo hi)
  else
    none
termination_by hi - lo
decreasing_by
  · have := lo_le_mid lo hi
    have := mid_lt_hi _hlt
    omega
  · have := lo_le_mid lo hi
    have := mid_lt_hi _hlt
    omega

/-- The sentinel the exported function returns when the target is absent:
`-1` as an `i32`. -/
def notFound : UInt32 := 0xFFFFFFFF

/-- The value the exported function returns: an index, or the sentinel. -/
def searchResult (xs : List UInt32) (target : UInt32) : UInt32 :=
  match searchAux xs target 0 xs.length with
  | some i => UInt32.ofNat i
  | none => notFound

private theorem getElem!_eq_of_getElem? {xs : List UInt32} {m : Nat} {v : UInt32}
    (h : xs[m]? = some v) : xs[m]! = v := by
  rw [List.getElem!_eq_getElem?_getD, h]; rfl

/-! ## One-step window lemmas

One unfolding of `searchAux` per branch of the compiled loop body, phrased so
the Iris loop proof can rewrite its invariant without touching the recursion
itself. -/

/-- Empty window: the search reports a miss. -/
theorem searchAux_none_of_ge {xs : List UInt32} {target : UInt32} {lo hi : Nat}
    (hge : ¬ lo < hi) : searchAux xs target lo hi = none := by
  rw [searchAux]
  simp only [hge, dif_neg, not_false_iff]

/-- Element below target: the answer comes from the upper half. -/
theorem searchAux_step_right {xs : List UInt32} {target v : UInt32} {lo hi : Nat}
    (hlt : lo < hi) (hget : xs[mid lo hi]? = some v) (hv : v < target) :
    searchAux xs target lo hi = searchAux xs target (mid lo hi + 1) hi := by
  rw [searchAux]
  simp only [hlt, dif_pos, hget, hv, if_pos]

/-- Element above target: the answer comes from the lower half. -/
theorem searchAux_step_left {xs : List UInt32} {target v : UInt32} {lo hi : Nat}
    (hlt : lo < hi) (hget : xs[mid lo hi]? = some v)
    (hv1 : ¬ v < target) (hv2 : target < v) :
    searchAux xs target lo hi = searchAux xs target lo (mid lo hi) := by
  rw [searchAux]
  simp only [hlt, dif_pos, hget, hv1, hv2, if_neg, if_pos, not_false_iff]

/-- Element equals target: the search stops at the midpoint. -/
theorem searchAux_hit {xs : List UInt32} {target v : UInt32} {lo hi : Nat}
    (hlt : lo < hi) (hget : xs[mid lo hi]? = some v)
    (hv1 : ¬ v < target) (hv2 : ¬ target < v) :
    searchAux xs target lo hi = some (mid lo hi) := by
  rw [searchAux]
  simp only [hlt, dif_pos, hget, hv1, hv2, if_neg, not_false_iff]

/-- Fold a concluded hit back into the exported function's return value. -/
theorem searchResult_of_aux_some {xs : List UInt32} {target : UInt32} {i : Nat}
    (h : searchAux xs target 0 xs.length = some i) :
    searchResult xs target = UInt32.ofNat i := by
  unfold searchResult
  rw [h]

/-- Fold a concluded miss back into the exported function's return value. -/
theorem searchResult_of_aux_none {xs : List UInt32} {target : UInt32}
    (h : searchAux xs target 0 xs.length = none) :
    searchResult xs target = notFound := by
  unfold searchResult
  rw [h]

/-- A reported hit is genuine. Sortedness is not needed for this direction. -/
theorem searchAux_some {xs : List UInt32} {target : UInt32} {i : Nat} :
    ∀ lo hi, searchAux xs target lo hi = some i →
      i < xs.length ∧ xs[i]! = target := by
  intro lo hi
  induction lo, hi using searchAux.induct (xs := xs) (target := target) with
  | case1 lo hi hlt hget =>
    intro h; rw [searchAux] at h; simp only [hlt, dif_pos, hget] at h; cases h
  | case2 lo hi hlt v hget hv ih =>
    intro h; rw [searchAux] at h
    simp only [hlt, dif_pos, hget, hv, if_pos] at h
    exact ih h
  | case3 lo hi hlt v hget hv1 hv2 ih =>
    intro h; rw [searchAux] at h
    simp only [hlt, dif_pos, hget, hv1, hv2, if_neg, if_pos, not_false_iff] at h
    exact ih h
  | case4 lo hi hlt v hget hv1 hv2 =>
    intro h; rw [searchAux] at h
    simp only [hlt, dif_pos, hget, hv1, hv2, if_neg, not_false_iff,
      Option.some.injEq] at h
    subst h
    obtain ⟨hlen, _⟩ := List.getElem?_eq_some_iff.mp hget
    have hvt : v = target :=
      UInt32.toNat_inj.mp (Nat.le_antisymm (Nat.not_lt.mp hv2) (Nat.not_lt.mp hv1))
    refine ⟨hlen, ?_⟩
    rw [List.getElem!_eq_getElem?_getD, hget, ← hvt]
    rfl
  | case5 lo hi hlt =>
    intro h; rw [searchAux] at h
    simp only [hlt, dif_neg, not_false_iff] at h; cases h

/-- If the target really sits inside the window, the search cannot report a
miss. Sortedness is what licenses discarding half the window. -/
theorem searchAux_ne_none_of_mem {xs : List UInt32} {target : UInt32}
    (hsorted : Sorted xs) :
    ∀ lo hi, hi ≤ xs.length → ∀ k, lo ≤ k → k < hi → xs[k]! = target →
      searchAux xs target lo hi ≠ none := by
  intro lo hi
  induction lo, hi using searchAux.induct (xs := xs) (target := target) with
  | case1 lo hi hlt hget =>
    intro hle k _ _ _
    exfalso
    have hml : mid lo hi < xs.length := Nat.lt_of_lt_of_le (mid_lt_hi hlt) hle
    rw [List.getElem?_eq_none_iff] at hget
    omega
  | case2 lo hi hlt v hget hv ih =>
    intro hle k hk1 hk2 hkv
    have hmk : mid lo hi < k := by
      rcases Nat.lt_or_ge (mid lo hi) k with h | h
      · exact h
      · exfalso
        have hml : mid lo hi < xs.length := Nat.lt_of_lt_of_le (mid_lt_hi hlt) hle
        have hle' := hsorted k (mid lo hi) h hml
        rw [hkv, getElem!_eq_of_getElem? hget] at hle'
        exact absurd hv (Nat.not_lt.mpr hle')
    rw [searchAux]
    simp only [hlt, dif_pos, hget, hv, if_pos]
    exact ih hle k hmk hk2 hkv
  | case3 lo hi hlt v hget hv1 hv2 ih =>
    intro hle k hk1 hk2 hkv
    have hkm : k < mid lo hi := by
      rcases Nat.lt_or_ge k (mid lo hi) with h | h
      · exact h
      · exfalso
        have hkl : k < xs.length := Nat.lt_of_lt_of_le hk2 hle
        have hle' := hsorted (mid lo hi) k h hkl
        rw [hkv, getElem!_eq_of_getElem? hget] at hle'
        exact absurd hv2 (Nat.not_lt.mpr hle')
    rw [searchAux]
    simp only [hlt, dif_pos, hget, hv1, hv2, if_neg, if_pos, not_false_iff]
    exact ih (Nat.le_trans (Nat.le_of_lt (mid_lt_hi hlt)) hle) k hk1 hkm hkv
  | case4 lo hi hlt v hget hv1 hv2 =>
    intro _ _ _ _ _
    rw [searchAux]
    simp only [hlt, dif_pos, hget, hv1, hv2, if_neg, not_false_iff]
    exact fun h => by cases h
  | case5 lo hi hlt =>
    intro _ k hk1 hk2 _
    exact absurd (Nat.lt_of_le_of_lt hk1 hk2) hlt

/-- A returned index is genuine: it is in range and holds the target. -/
theorem searchResult_hit {xs : List UInt32} {target : UInt32}
    (h : searchResult xs target ≠ notFound) (hlen : xs.length < 2 ^ 31) :
    (searchResult xs target).toNat < xs.length ∧
      xs[(searchResult xs target).toNat]! = target := by
  unfold searchResult at h ⊢
  cases hs : searchAux xs target 0 xs.length with
  | none => rw [hs] at h; exact absurd rfl h
  | some i =>
    dsimp only
    obtain ⟨hi1, hi2⟩ := searchAux_some 0 xs.length hs
    have hti : (UInt32.ofNat i).toNat = i := by
      have hsz : UInt32.size = 4294967296 := rfl
      apply UInt32.toNat_ofNat_of_lt; omega
    rw [hti]
    exact ⟨hi1, hi2⟩

/-- The sentinel is returned only when the target really is absent. Sortedness
is required: without it the halving can step past an occurrence. -/
theorem searchResult_miss {xs : List UInt32} {target : UInt32}
    (hsorted : Sorted xs) (h : searchResult xs target = notFound)
    (hlen : xs.length < 2 ^ 31) :
    ∀ k, k < xs.length → xs[k]! ≠ target := by
  intro k hk hkv
  unfold searchResult at h
  cases hs : searchAux xs target 0 xs.length with
  | none =>
    exact searchAux_ne_none_of_mem hsorted 0 xs.length (Nat.le_refl _) k
      (Nat.zero_le _) hk hkv hs
  | some i =>
    rw [hs] at h
    dsimp only at h
    obtain ⟨hi1, _⟩ := searchAux_some 0 xs.length hs
    have hti : (UInt32.ofNat i).toNat = i := by
      have hsz : UInt32.size = 4294967296 := rfl
      apply UInt32.toNat_ofNat_of_lt; omega
    have : i = 4294967295 := by rw [← hti, h]; rfl
    omega

end Project.BinarySearch.Pure
