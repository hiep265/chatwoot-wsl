# Aftercare Sequences Phase 1-2 Design

**Date:** 2026-03-18

## Goal

Implement the first usable slice of the `Aftercare Sequences` subsystem directly in `chatwoot-wsl`:

- create and store aftercare sequence enrollments from `AiControlPanel`
- validate Messenger/Instagram eligibility before activation
- track opt-in request/subscription state in Chatwoot
- expose a UI tab and creation dialog for operators

## Architecture

- `chatwoot-wsl` is the only source of truth for sequence templates, enrollments, steps, opt-in state, and audit events.
- `chatbotlevan` and `kimi-cli-fork` are intentionally out of scope for this slice.
- The implementation adds a new `Aftercare` namespace with dedicated models, services, jobs, and account-scoped API endpoints.

## Scope

### Included

- Sequence templates and cloned enrollment steps in the Chatwoot DB
- Eligibility gate for Messenger and Instagram conversations
- Opt-in request state machine and webhook ingestion contract
- `AiControlPanel` tab for list/status visibility
- `AiControlPanel` modal for creating aftercare enrollments

### Excluded

- AI draft generation
- scheduled auto-send
- Meta delivery retry logic
- deep linking outside `AiControlPanel`

## Data Model

- `aftercare_sequences`
- `aftercare_sequence_steps`
- `aftercare_enrollments`
- `aftercare_enrollment_steps`
- `aftercare_opt_in_subscriptions`
- `aftercare_audit_events`

Global default sequences are seeded in the initial migration so the UI has usable templates immediately.

## Backend Flow

1. UI requests available sequences and eligibility for a selected conversation.
2. Chatwoot validates supported channel and message window.
3. Chatwoot creates enrollment, clones steps, creates opt-in subscription, records audit event.
4. Chatwoot enqueues `Aftercare::RequestOptInJob`.
5. Job marks the subscription as requested through a small provider abstraction.
6. A webhook-style API endpoint can mark the subscription as subscribed/expired/revoked and update the enrollment state.

## UI Flow

1. Operator opens `AiControlPanel`.
2. Operator clicks `Tư vấn sau mua` from a selected live conversation.
3. Dialog shows conversation snapshot, eligibility, sequence, note, timezone, anchor time, and editable steps.
4. Save creates the enrollment and refreshes the new `Tư vấn sau mua` tab.

## Testing

- request specs for list/create/eligibility/webhook flow
- service spec for eligibility decisions
- model specs for aftercare enums/associations if needed
- Vitest coverage for `AiControlPanel` aftercare dialog and tab rendering
