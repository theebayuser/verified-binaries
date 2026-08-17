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

-- The symbolic opt3 proof: standard axioms only. This is the audit line
-- that matters most: the universal statement must never pick up
-- `Lean.ofReduceBool`.
#print axioms Project.BinarySearchOpt3.TotalProof.binarySearchOpt3Spec_holds
#print axioms Project.BinarySearchOpt3.TotalProof.terminates_hit
#print axioms Project.BinarySearchOpt3.TotalProof.terminates_miss

-- Concrete regressions: these carry `native_decide`.
#print axioms Project.BinarySearch.Smoke.agrees_hit_middle
#print axioms Project.BinarySearchOpt3.Smoke.agrees_hit_middle
#print axioms Project.BinarySearchOpt3.Equivalence.equivalent_hit_middle
