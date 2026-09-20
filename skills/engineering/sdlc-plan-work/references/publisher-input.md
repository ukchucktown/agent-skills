# Publisher input

Use one of these version 1 shapes after the approval boundaries.

## One issue

```json
{
  "schemaVersion": 1,
  "mode": "single",
  "repository": "owner/repository",
  "issue": {
    "title": "Deliver one reviewable outcome",
    "body": "The approved issue body"
  }
}
```

## Coordinated feature

```json
{
  "schemaVersion": 1,
  "mode": "feature",
  "repository": "owner/repository",
  "parent": {
    "title": "Build the approved feature",
    "body": "The approved parent specification"
  },
  "children": [
    {
      "key": "foundation",
      "title": "Build the foundation",
      "body": "The approved child issue body",
      "dependsOn": []
    },
    {
      "key": "delivery",
      "title": "Deliver the feature",
      "body": "The approved child issue body",
      "dependsOn": ["foundation"]
    }
  ]
}
```

Use stable, short keys only inside the plan. The publisher replaces `{parent}`
in a child body with the created parent issue number.
