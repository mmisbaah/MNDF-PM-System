# Dedicated System Administrator runbook

The System Administrator is a restricted, non-supervisory account. Only the current Admin In-Charge or Admin Clerk appointment holders may operate it. Access requires the account password, authenticator verification, and a current System Authorizer approval. Approval lasts seven days and becomes invalid when either eligible operator appointment changes.

## Permitted work

- Add and correct personnel name, rank or grade, dummy unique ID, category, organizational placement, appointment, and additional responsibilities.
- Provision a pilot login and issue or reset a temporary password.
- Deactivate a departed or suspended person and collect ordinary reports.

The account cannot evaluate, approve, adjust scores, participate in grievances, change templates, authorize corrections, or assume supervisory authority.

## Personnel onboarding

1. Confirm the organizational node and reusable appointment already exist.
2. Search the dummy unique ID to prevent duplicates.
3. Enter identity and placement, select the appointment, review its standard responsibility description, and add only genuinely additional responsibilities.
4. Create the login and set a minimum 12-character temporary password.
5. Give the login and temporary password directly to the user through the locally approved method. Never record it in a spreadsheet, ticket, or chat.
6. Confirm that first sign-in requires a private password replacement.

Prefer deactivation over removal when a person has historical records. Removal is suitable only for a mistaken unused entry and must follow application safeguards. Never manipulate personnel or account rows directly in PostgreSQL.

## Appointment and access changes

When an Admin In-Charge or Admin Clerk appointment changes, request new Authorizer approval before further use. When the System Authorizer changes, the successor receives active authority; the outgoing holder retains read, export, and handover functions only for three days. Record discrepancies as incidents rather than granting extra roles to work around them.

At the end of each session, sign out and verify that no temporary password or exported report remains in Downloads, clipboard history, screenshots, or an uncontrolled location.

