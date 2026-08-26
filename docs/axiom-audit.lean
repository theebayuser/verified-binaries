import Project

/-!
Axiom audit. Run with `just axioms`.

Expected, and the point of separating the three groups:

* the model lemmas and the WP rules depend only on Lean's standard axioms
  (`propext`, `Quot.sound`, and `Classical.choice` where classical reasoning
  is used);
* the symbolic memory proofs additionally carry inherited axioms of the form
  `Wasm.SepLogic.<lemma>._native.bv_decide.ax_*`, for exactly four upstream
  lemmas: `u32Byte_reassemble`, which every upstream heap rule depends on,
  and `Mem.read32_byte1` through `read32_byte3`, which decompose a stored
  word into its bytes. The pinned upstream CodeLib proves those byte-level
  lemmas with `bv_decide`, whose LRAT certificate check runs through compiled
  code, so their trust base is the Lean compiler. Nothing local can remove
  them. The optimized chain inherits the first; the unoptimized chain also
  inherits the other three, because its heap-agreement lemma uses them to
  relate each written array word to the ghost byte map.
  `docs/check-axioms.py` accepts those axioms by exact name and no other;
* the concrete regressions, and anything built from them, additionally carry a
  `native_decide` axiom. That is why they are kept in `Smoke.lean` and why no
  universal claim is allowed to depend on them.

`docs/check-axioms.py` parses this output and fails if a theorem outside
`Smoke` / `Equivalence` carries anything beyond the standard axioms and the
named inherited axioms, or if the audit produced fewer records than there are
`#print axioms` lines here. CI runs both.
-/

open Project.BinarySearch.Pure

-- Model: standard axioms only.
#print axioms searchAux_some
#print axioms searchAux_ne_none_of_mem
#print axioms searchResult_hit
#print axioms searchResult_miss

-- Total-WP rules: standard axioms only.
#print axioms Wasm.SmallStep.twp_shrU
#print axioms Wasm.SmallStep.twp_gtU
#print axioms Wasm.SmallStep.twp_geU

-- The symbolic opt3 proof: standard axioms plus one inherited upstream
-- `bv_decide` axiom described above. These are the audit lines that matter
-- most: a universal statement must never pick up a `native_decide` axiom or
-- any other unexplained one.
#print axioms Project.BinarySearchOpt3.TotalProof.binarySearchOpt3Spec_holds
#print axioms Project.BinarySearchOpt3.TotalProof.binarySearchOpt3_result_unique
#print axioms Project.BinarySearchOpt3.TotalProof.binarySearchOpt3_never_traps
#print axioms Project.BinarySearchOpt3.TotalProof.terminates_hit
#print axioms Project.BinarySearchOpt3.TotalProof.terminates_miss

-- The symbolic opt0 proof: the same trust base as the opt3 one, standard
-- axioms plus the inherited `bv_decide` axioms. Its heap-agreement lemma
-- decomposes each written array word into bytes through the upstream
-- `Mem.read32_byte` lemmas, so it inherits their three axioms in addition
-- to the one the optimized proof carries.
#print axioms Project.BinarySearch.TotalProof.binarySearchSpec_holds
#print axioms Project.BinarySearch.TotalProof.binarySearch_result_unique
#print axioms Project.BinarySearch.TotalProof.binarySearch_never_traps
#print axioms Project.BinarySearch.TotalProof.terminates_hit
#print axioms Project.BinarySearch.TotalProof.terminates_miss

-- The symbolic equivalence of the two artifacts: it composes the two
-- symbolic proofs and runs neither binary, so it carries no `native_decide`
-- axiom. Its namespace is chosen so that the checker holds it to the
-- symbolic standard.
#print axioms Project.BinarySearchOpt3.SymbolicEquivalence.equivalent

-- Concrete regressions: every one of these carries a `native_decide` axiom,
-- and the list below is exhaustive, so `docs/check-axioms.py` can hold the
-- quarantine boundary rather than trusting a spot check.
#print axioms Project.BinarySearchOpt3.Smoke.agrees_hit_middle
#print axioms Project.BinarySearchOpt3.Smoke.agrees_hit_first
#print axioms Project.BinarySearchOpt3.Smoke.agrees_hit_last
#print axioms Project.BinarySearchOpt3.Smoke.agrees_miss_between
#print axioms Project.BinarySearchOpt3.Smoke.agrees_miss_below
#print axioms Project.BinarySearchOpt3.Smoke.agrees_miss_above
#print axioms Project.BinarySearchOpt3.Smoke.agrees_empty
#print axioms Project.BinarySearchOpt3.Smoke.agrees_duplicates
#print axioms Project.BinarySearchOpt3.Smoke.agrees_duplicates_upper

#print axioms Project.BinarySearch.Smoke.agrees_hit_middle
#print axioms Project.BinarySearch.Smoke.agrees_miss_between
#print axioms Project.BinarySearch.Smoke.agrees_empty

#print axioms Project.BinarySearchOpt3.Equivalence.equivalent_hit_middle
#print axioms Project.BinarySearchOpt3.Equivalence.equivalent_miss_between
#print axioms Project.BinarySearchOpt3.Equivalence.equivalent_empty
