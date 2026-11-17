Title: Cancel button on the appointment card

As a patient, I want a blue "Cancel" button at the top right of each appointment card that opens a modal with a dropdown of cancellation reasons and a red "Confirm" button, so that I can cancel an upcoming appointment and free the slot for someone else.

Acceptance criteria:
- The button uses the primary-blue style and sits 16 pixels from the top right corner of the card.
- The modal dropdown lists five reasons, loaded from the cancellation_reasons table.
- Given my appointment starts more than 24 hours from now, when I press "Confirm", then my appointment list shows it as cancelled and the slot shows as available to book.
- Given my appointment starts in less than 24 hours, then the button is greyed out and a tooltip shows the clinic phone number.
- Given the cancellation cannot be saved, then the modal shows that the appointment is still booked.
