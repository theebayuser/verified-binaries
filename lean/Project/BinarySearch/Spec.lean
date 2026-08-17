import Project.BinarySearch.Program

/-!
# Specification for the unoptimized `binary_search` artifact

Not yet stated. The opt0 build spills its loop state to a shadow-stack frame
in linear memory and reads the stack pointer through `global.get`/`global.set`,
and the pinned CodeLib revision carries no total-WP rules for globals, so the
symbolic statement for this artifact is deferred until they exist upstream.

What covers this artifact today is `Project.BinarySearch.Smoke`: concrete
runs of the decoded binary checked against the pure model, plus the
observational-equivalence theorems in `Project.BinarySearchOpt3.Equivalence`
tying it to the optimized artifact. The symbolic total-correctness statement
and proof live on the optimized side, in `Project.BinarySearchOpt3.Spec` and
`Project.BinarySearchOpt3.TotalProof`.

No `@[spec_of]` tag here on purpose: nothing should report a trivial
placeholder as a specification.
-/

namespace Project.BinarySearch.Spec

/-- Placeholder, deliberately untagged; see the module docstring. -/
def BinarySearchSpec : Prop :=
  True

end Project.BinarySearch.Spec
