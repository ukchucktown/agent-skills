Key: CL-6
Title: Reminder before an appointment

As a patient, I want a reminder email two days before my appointment so that I do not forget it.

Acceptance criteria:
- Given I have an appointment in two days, when the daily reminder run starts, then I receive one email with the date, the time, and the clinician.
- Given I open the email, when I select "Cancel this appointment", then I arrive at the online cancellation of that appointment.
- Given my appointment is cancelled, when the daily reminder run starts, then I receive no email for it.
