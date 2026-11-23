Key: EX-2
Title: Approve or reject an expense claim

As a manager, I want to approve or reject a submitted expense claim so that only valid claims are paid.

Acceptance criteria:
- Given a claim has the state "submitted", when I approve it, then it has the state "approved".
- Given a claim has the state "submitted", when I reject it with a reason, then it has the state "rejected" and the claim keeps the reason.

Notes: Depends on EX-1.
