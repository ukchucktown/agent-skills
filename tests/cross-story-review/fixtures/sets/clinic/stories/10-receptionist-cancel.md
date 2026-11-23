Key: CL-10
Title: Cancel an appointment for a patient at the desk

As a receptionist, I want to cancel an appointment for a patient who calls so that the slot is free and the patient gets a confirmation.

Acceptance criteria:
- Given a patient calls about an appointment, when I cancel it at the desk, then the appointment shows as cancelled, the slot is free to book, and the patient receives a confirmation email.
- Given the appointment starts in less than 24 hours, when I cancel it, then I must select a reason from the list before I can confirm.

Notes: Depends on CL-1. The 24-hour limit of CL-3 applies to patients online, not to the desk.
