Title: Say which input failed validation

As an integration developer who calls the booking API from a partner clinic system, I want a rejected request to tell me which input failed validation and why, so that I can correct my request without a support ticket.

Acceptance criteria:
- Given I send a booking request with one invalid field, when the API rejects it, then the response names that field and gives the reason.
- Given I send a booking request with three invalid fields, when the API rejects it, then the response names all three fields, each with its reason.
- Given I send a valid booking request, then the response has no validation errors and the booking is created.
- Given I send a request with no credentials, then the response says that sign-in is required and names no field.
