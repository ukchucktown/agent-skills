# Cleanup safety

The final merge plan classifies every Git worktree before it changes local
state.

- The stable checkout always remains.
- A dirty worktree remains with reason `dirty-worktree`.
- A branch that has no matching merged pull request evidence remains with
  reason `merge-evidence-missing`.
- Cleanup removes a clean child worktree with a merged child pull request only
  after the final pull request merges.
- Cleanup removes a clean integration worktree only after its exact candidate
  merges into the stable branch.

If removal fails, the report changes that item to retained and records the
error. Cleanup never forces removal of a dirty worktree.
