import Project.BinarySearch.Program

/-!
# Specification for `binary_search`
-/

namespace Project.BinarySearch.Spec

open Wasm

/-- TODO: state and prove the behaviour of the wasm export `binary_search`.

Informal spec:
Describe what `binary_search` computes here, then replace `True` with a
`TerminatesWith` / `PartiallyMeets` statement over `«module»` (the decoded
program emitted into `Program.lean`). -/
@[spec_of "rust-exported" "binary_search::binary_search"]
def BinarySearchSpec : Prop :=
  True

end Project.BinarySearch.Spec
