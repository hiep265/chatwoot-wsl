# Aftercare Sequences Phase 3 Design

## Goal

Implement the Phase 3 drafting lane for `Aftercare Sequences` so Chatwoot can:

- generate AI drafts for each enabled enrollment step,
- preview those drafts in `AiControlPanel`,
- regenerate a step draft on demand,
- keep Chatwoot as the source of truth for draft content, versions, and audit state.

## Scope

This phase adds the missing `draft generation` lane described in [SOLUTION_POST_PURCHASE_AFTERCARE_MVP](/home/hiep/Desktop/chatbot/chatbotlevan/docs/SOLUTION_POST_PURCHASE_AFTERCARE_MVP.md):

1. `chatwoot-wsl` owns draft storage, draft jobs, preview APIs, regenerate actions, and UI rendering.
2. `chatbotlevan` exposes a narrow internal HTTP contract that turns structured aftercare context into one draft response.
3. `kimi-cli-fork` runs a dedicated internal-only `aftercare_drafter` agent with a strict JSON output contract.

This phase does not add:

1. final scheduled sending,
2. final refresh-before-send scheduling,
3. outbound delivery via Meta,
4. pause/cancel/retry send workflows beyond draft regeneration.

## Architecture

### Chatwoot-native draft lane

When an enrollment is created, Chatwoot will enqueue one draft job per enabled step. Each job:

1. marks the step as `draft_status=pending`,
2. builds a structured snapshot from the enrollment, step, sequence, and recent conversation messages,
3. POSTs that payload to `chatbotlevan`,
4. stores the returned draft text and metadata on the step,
5. records an aftercare audit event.

The same service is reused by a regenerate endpoint so operators can refresh a single step draft from the tab detail view.

### Internal AI bridge contract

`chatbotlevan` receives a structured payload and returns JSON only. The contract is intentionally narrow:

Request fields:

- account / conversation / contact identifiers
- channel metadata
- sequence context
- enrollment context
- step context
- recent messages capped at the latest 30

Response fields:

- `draft_text`
- `summary`
- `version_fingerprint`
- optional `warnings`

`chatbotlevan` does not store draft state. It only validates input, runs the dedicated Kimi agent, parses JSON, and returns the result.

### Dedicated Kimi agent

`kimi-cli-fork` gets a new `aftercare_drafter` agent that:

1. is internal-only,
2. has no customer-facing tools,
3. outputs JSON only,
4. writes concise, safe, follow-up copy grounded in the sequence note, step instructions, and recent messages.

This keeps aftercare drafting isolated from the default sales/customer prompt.

## Data model changes

`aftercare_enrollment_steps` gains fields for persisted draft state:

- `draft_body`
- `draft_summary`
- `draft_version`
- `draft_generated_at`
- `draft_input_snapshot`
- `draft_error`

`draft_status` continues to express lifecycle (`not_requested`, `pending`, `ready`, `failed_generation`) while the new columns store the latest successful or failed result.

## API/UI changes

### Chatwoot API

Add:

1. `POST /api/v1/accounts/:account_id/aftercare/enrollments/:enrollment_id/steps/:id/regenerate_draft`
2. richer enrollment payloads that include the draft fields for each step

### AiControlPanel

The `Aftercare` tab will show:

1. current draft status,
2. preview text when available,
3. regenerate action per step,
4. inline loading/error feedback for regenerate.

The create flow stays asynchronous: enrollment creation succeeds first, then draft jobs fill the previews shortly after.

## Error handling

If draft generation fails:

1. the step becomes `draft_status=failed_generation`,
2. `draft_error` stores the latest error message,
3. the enrollment remains visible and recoverable,
4. regenerate can retry the same step later.

If `chatbotlevan` returns malformed or empty output, Chatwoot treats that as a failed generation and records the issue in the step plus audit trail.

## Testing strategy

### `chatwoot-wsl`

1. request specs for enrollment payload and regenerate endpoint
2. service/job specs for draft generation success and failure paths
3. frontend coverage for draft preview and regenerate interactions

### `chatbotlevan`

1. route tests for the internal draft endpoint
2. service tests for request shaping, message trimming, and JSON parsing

### `kimi-cli-fork`

1. agent file smoke verification through existing `KimiCliManager` integration tests or a focused unit test that resolves the new agent file

## Notes

This design preserves the product decision already locked in the solution docs:

- Chatwoot is the workflow and data owner.
- `chatbotlevan` is a thin AI bridge.
- `kimi-cli-fork` is only the drafting runtime.
