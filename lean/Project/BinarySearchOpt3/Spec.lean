import Project.BinarySearchOpt3.Program

/-!
# Specification for `binary_search_opt3`
-/

namespace Project.BinarySearchOpt3.Spec

open Wasm

/-- TODO: state and prove the behaviour of the wasm export `binary_search_opt3`.

Informal spec:
Describe what `binary_search_opt3` computes here, then replace `True` with a
`TerminatesWith` / `PartiallyMeets` statement over `«module»` (the decoded
program emitted into `Program.lean`). -/
@[spec_of "rust-exported" "binary_search_opt3::binary_search_opt3"]
def BinarySearchOpt3Spec : Prop :=
  True

end Project.BinarySearchOpt3.Spec
