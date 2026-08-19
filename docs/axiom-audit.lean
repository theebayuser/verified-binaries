import Project

/-!
Axiom audit. Run with `just axioms`.

Expected, and the point of separating the two groups:

* the model lemmas and the WP rules depend only on Lean's standard axioms
  (`propext`, `Quot.sound`, and `Classical.choice` where classical reasoning
  is used);
* the concrete regressions, and anything built from them, additionally carry a
  `native_decide` axiom. That is why they are kept in `Smoke.lean` and why no
  universal claim is allowed to depend on them.

`docs/check-axioms.py` parses this output and fails if a theorem outside
`Smoke` / `Equivalence` carries anything beyond the standard axioms, or if the
audit produced fewer records than there are `#print axioms` lines here. CI runs
both.
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

-- The symbolic opt3 proof: standard axioms only. These are the audit lines
-- that matter most: a universal statement must never pick up a
-- `native_decide` axiom.
#print axioms Project.BinarySearchOpt3.TotalProof.binarySearchOpt3Spec_holds
#print axioms Project.BinarySearchOpt3.TotalProof.binarySearchOpt3_result_unique
#print axioms Project.BinarySearchOpt3.TotalProof.binarySearchOpt3_never_traps
#print axioms Project.BinarySearchOpt3.TotalProof.terminates_hit
#print axioms Project.BinarySearchOpt3.TotalProof.terminates_miss

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
