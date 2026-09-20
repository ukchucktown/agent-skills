# Review evidence

Each review file is a JSON object with five fields:

```json
{
  "schemaVersion": 1,
  "axis": "standards",
  "candidateCommit": "0123456789abcdef0123456789abcdef01234567",
  "verdict": "pass",
  "summary": "The change follows the repository module and test guidance."
}
```

Use `standards` or `specification` for `axis`. Use the full object ID from the
candidate file. Set `verdict` to `pass` only when that axis has no unresolved
finding. The summary must state what the review established.

Do not reuse evidence after any commit changes. Repeat the review against the
new candidate before you edit a failing verdict.
