Title: Cancel an upcoming appointment online

As a patient, I want to cancel an upcoming appointment online so that the slot is free for someone else and I avoid the missed-appointment fee.

Acceptance criteria:
- Given I have an appointment that starts 24 hours or more from now, when I cancel it, then my appointment list shows it as cancelled and the slot shows as available to book.
- Given my appointment starts in less than 24 hours, when I try to cancel it, then I see that online cancellation is closed and I see the clinic phone number.
- Given I am not signed in, when I open the cancel link from my reminder email, then I am asked to sign in before anything changes.
- Given the cancellation cannot be saved, when I confirm, then I see that the appointment is still booked.

Notes: The 24-hour limit is clinic policy (Patient Handbook, section 4). The missed-appointment fee applies only to appointments that are not cancelled.

Implementation notes:
1. Add column cancelled_at TIMESTAMP NULL and cancelled_by_user_id BIGINT to the appointments table, with an index on (clinician_id, cancelled_at).
2. Create AppointmentCancellationService with a method cancel(appointmentId, userId) that opens a transaction, takes a row lock with SELECT FOR UPDATE, sets cancelled_at, and publishes an AppointmentCancelled event on the booking topic.
3. Add CancellationController with POST /api/v2/appointments/{id}/cancel, returning 204 on success, 409 inside the 24-hour window, 401 when unauthenticated.
4. In the front end, add CancelAppointmentDialog.tsx using the shared ConfirmDialog component and call the endpoint through the useMutation hook; invalidate the appointments query on success.
5. SlotAvailabilityProjector must subscribe to AppointmentCancelled and set slot.status = 'OPEN'.
6. Write a Flyway migration V87__appointment_cancellation.sql and a rollback script.
7. Use feature flag patient_portal.cancel_online, default off.
