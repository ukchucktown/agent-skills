Bug: cancelled appointment still shows as booked in Safari

Steps:
1. Sign in as a patient in Safari 18.
2. Cancel an appointment that starts more than 24 hours from now.

Expected: the slot shows as available to book.
Actual: the appointment shows as cancelled for the patient, but the slot still shows as booked for everyone else until the page cache expires.
