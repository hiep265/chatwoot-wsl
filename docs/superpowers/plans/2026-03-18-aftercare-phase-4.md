# Aftercare Phase 4 Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Phase 4 of Aftercare Sequences in Chatwoot: scheduled dispatch, direct Meta send from Chatwoot, retry/cancel controls, and audit/dispatch hardening.

**Architecture:** `chatwoot-wsl` remains the only source of truth. Sidekiq scans due aftercare steps, dispatches one step idempotently, refreshes stale drafts when needed, creates a real outgoing Chatwoot message for delivery, and stores both audit events and a dedicated aftercare dispatch log. The AI bridge is unchanged except that existing step drafts are consumed by Chatwoot during send.

**Tech Stack:** Ruby on Rails, ActiveRecord, Sidekiq/ActiveJob, RSpec, Vue 3, existing Chatwoot Meta delivery services.

---

### Task 1: Add aftercare dispatch persistence and read-model fields

**Files:**
- Create: `db/migrate/20260318190000_create_aftercare_dispatch_logs.rb`
- Create: `app/models/aftercare_dispatch_log.rb`
- Modify: `app/models/aftercare_enrollment.rb`
- Modify: `app/models/aftercare_enrollment_step.rb`
- Test: `spec/models/aftercare_dispatch_log_spec.rb`

- [ ] **Step 1: Write the failing model spec**

```ruby
RSpec.describe AftercareDispatchLog, type: :model do
  it 'belongs to enrollment and step and requires attempt_key' do
    log = described_class.new

    expect(log).not_to be_valid
    expect(log.errors[:attempt_key]).to be_present
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/models/aftercare_dispatch_log_spec.rb`
Expected: FAIL because the model/table do not exist yet.

- [ ] **Step 3: Write minimal implementation**

Add a dispatch log table and model with:
- `aftercare_enrollment_id`
- `aftercare_enrollment_step_id`
- `message_id`
- `attempt_key`
- `status`
- `provider`
- `provider_message_id`
- `error_message`
- `sent_at`
- `metadata`

Also add associations on `AftercareEnrollment` / `AftercareEnrollmentStep`.

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/models/aftercare_dispatch_log_spec.rb`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add db/migrate/20260318190000_create_aftercare_dispatch_logs.rb app/models/aftercare_dispatch_log.rb app/models/aftercare_enrollment.rb app/models/aftercare_enrollment_step.rb spec/models/aftercare_dispatch_log_spec.rb
git commit -m "feat: add aftercare dispatch logs"
```

### Task 2: Add scheduler and direct dispatch services/jobs

**Files:**
- Create: `app/jobs/aftercare/process_due_steps_job.rb`
- Create: `app/jobs/aftercare/dispatch_step_job.rb`
- Create: `app/services/aftercare/dispatch_step_service.rb`
- Create: `app/services/aftercare/refresh_step_draft_service.rb`
- Modify: `app/jobs/trigger_scheduled_items_job.rb`
- Modify: `config/schedule.yml` (only if needed for existing cron integration expectations)
- Test: `spec/jobs/aftercare/process_due_steps_job_spec.rb`
- Test: `spec/jobs/aftercare/dispatch_step_job_spec.rb`
- Test: `spec/services/aftercare/dispatch_step_service_spec.rb`
- Test: `spec/jobs/trigger_scheduled_items_job_spec.rb`

- [ ] **Step 1: Write the failing scheduler spec**

```ruby
it 'enqueues dispatch jobs for active due aftercare steps only' do
  described_class.perform_now

  expect(Aftercare::DispatchStepJob).to have_been_enqueued.with(step.id)
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/jobs/aftercare/process_due_steps_job_spec.rb spec/jobs/trigger_scheduled_items_job_spec.rb`
Expected: FAIL because the job/service do not exist and trigger job does not call them.

- [ ] **Step 3: Write the failing dispatch service spec**

```ruby
it 'creates an outgoing message, records a sent dispatch log, and marks the step sent' do
  described_class.new(step: step).perform

  expect(step.reload.status).to eq('sent')
  expect(step.aftercare_dispatch_logs.last.status).to eq('sent')
end
```

Add adjacent failing examples for:
- stale draft refresh before send
- inactive enrollment blocking send
- expired/revoked subscription blocking send
- duplicate retry idempotency not sending twice
- provider failure marking step `failed`
- completion when all enabled steps are sent

- [ ] **Step 4: Run test to verify it fails**

Run: `bundle exec rspec spec/services/aftercare/dispatch_step_service_spec.rb spec/jobs/aftercare/dispatch_step_job_spec.rb`
Expected: FAIL with missing classes/behavior.

- [ ] **Step 5: Write minimal implementation**

Implementation rules:
- Scan only enabled steps with `scheduled` status whose `scheduled_for <= Time.current`
- Require enrollment `active` and subscription `subscribed`
- Mark step `sending` during dispatch
- Refresh draft if no ready draft or if draft is stale near send time
- Create a real Chatwoot outgoing message using the enrollment conversation and `is_bot_generated`
- Let Chatwoot’s normal `SendReplyJob` deliver to Meta
- Create/update dispatch log rows per attempt
- On success: mark step `sent`, store `message_id`, `sent_at`, clear errors
- On failure: mark step `failed`, persist error, keep enrollment active unless token/policy says `expired`/`paused`

- [ ] **Step 6: Run tests to verify they pass**

Run: `bundle exec rspec spec/services/aftercare/dispatch_step_service_spec.rb spec/jobs/aftercare/dispatch_step_job_spec.rb spec/jobs/aftercare/process_due_steps_job_spec.rb spec/jobs/trigger_scheduled_items_job_spec.rb`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add app/jobs/aftercare/process_due_steps_job.rb app/jobs/aftercare/dispatch_step_job.rb app/services/aftercare/dispatch_step_service.rb app/services/aftercare/refresh_step_draft_service.rb app/jobs/trigger_scheduled_items_job.rb config/schedule.yml spec/jobs/aftercare/process_due_steps_job_spec.rb spec/jobs/aftercare/dispatch_step_job_spec.rb spec/services/aftercare/dispatch_step_service_spec.rb spec/jobs/trigger_scheduled_items_job_spec.rb
git commit -m "feat: schedule and dispatch aftercare steps"
```

### Task 3: Add operator retry/cancel APIs

**Files:**
- Modify: `config/routes.rb`
- Modify: `app/controllers/api/v1/accounts/aftercare/enrollments_controller.rb`
- Modify: `app/controllers/api/v1/accounts/aftercare/enrollment_steps_controller.rb`
- Create: `app/services/aftercare/cancel_enrollment_service.rb`
- Create: `app/services/aftercare/retry_step_service.rb`
- Test: `spec/controllers/api/v1/accounts/aftercare/enrollments_controller_spec.rb`
- Test: `spec/controllers/api/v1/accounts/aftercare/enrollment_steps_controller_spec.rb`
- Test: `spec/services/aftercare/cancel_enrollment_service_spec.rb`
- Test: `spec/services/aftercare/retry_step_service_spec.rb`

- [ ] **Step 1: Write the failing controller specs**

```ruby
it 'cancels an enrollment and its unsent steps' do
  post "/api/v1/accounts/#{account.id}/aftercare/enrollments/#{enrollment.id}/cancel"

  expect(enrollment.reload.status).to eq('cancelled')
end

it 'retries a failed step by requeueing dispatch' do
  post "/api/v1/accounts/#{account.id}/aftercare/enrollments/#{enrollment.id}/steps/#{step.id}/retry"

  expect(Aftercare::DispatchStepJob).to have_been_enqueued.with(step.id)
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/controllers/api/v1/accounts/aftercare/enrollments_controller_spec.rb spec/controllers/api/v1/accounts/aftercare/enrollment_steps_controller_spec.rb`
Expected: FAIL because routes/actions do not exist.

- [ ] **Step 3: Write minimal implementation**

Behavior:
- `cancel` marks enrollment `cancelled`, stamps `cancelled_at`, cancels unsent enabled steps, records audit
- `retry` only allows failed/scheduled steps on non-cancelled enrollments, clears transient error state, records audit, and enqueues dispatch

- [ ] **Step 4: Run tests to verify they pass**

Run: `bundle exec rspec spec/services/aftercare/cancel_enrollment_service_spec.rb spec/services/aftercare/retry_step_service_spec.rb spec/controllers/api/v1/accounts/aftercare/enrollments_controller_spec.rb spec/controllers/api/v1/accounts/aftercare/enrollment_steps_controller_spec.rb`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add config/routes.rb app/controllers/api/v1/accounts/aftercare/enrollments_controller.rb app/controllers/api/v1/accounts/aftercare/enrollment_steps_controller.rb app/services/aftercare/cancel_enrollment_service.rb app/services/aftercare/retry_step_service.rb spec/services/aftercare/cancel_enrollment_service_spec.rb spec/services/aftercare/retry_step_service_spec.rb spec/controllers/api/v1/accounts/aftercare/enrollments_controller_spec.rb spec/controllers/api/v1/accounts/aftercare/enrollment_steps_controller_spec.rb
git commit -m "feat: add aftercare retry and cancel controls"
```

### Task 4: Expose retry/cancel controls in AiControlPanel

**Files:**
- Modify: `app/javascript/dashboard/api/aiControl.js`
- Modify: `app/javascript/dashboard/routes/dashboard/aiControl/pages/AiControlPanel.vue`
- Modify: `app/javascript/dashboard/routes/dashboard/aiControl/pages/specs/AiControlPanel.spec.js`

- [ ] **Step 1: Write the failing UI/API specs**

Add expectations that:
- the aftercare tab shows `Retry` for failed steps
- the aftercare tab shows `Cancel enrollment`
- clicking them hits the right API and updates local state

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/controllers/api/v1/accounts/aftercare/enrollments_controller_spec.rb spec/controllers/api/v1/accounts/aftercare/enrollment_steps_controller_spec.rb`
Run: `pnpm vitest app/javascript/dashboard/routes/dashboard/aiControl/pages/specs/AiControlPanel.spec.js`
Expected: FAIL because the client/UI do not support these actions yet.

- [ ] **Step 3: Write minimal implementation**

Add:
- `cancelAftercareEnrollment`
- `retryAftercareStep`
- loading/disabled states
- optimistic or refreshed state updates after success

- [ ] **Step 4: Run test to verify it passes**

Run: `pnpm vitest app/javascript/dashboard/routes/dashboard/aiControl/pages/specs/AiControlPanel.spec.js`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/javascript/dashboard/api/aiControl.js app/javascript/dashboard/routes/dashboard/aiControl/pages/AiControlPanel.vue app/javascript/dashboard/routes/dashboard/aiControl/pages/specs/AiControlPanel.spec.js
git commit -m "feat: add aftercare operator controls"
```

### Task 5: Verify Phase 4 end-to-end behavior

**Files:**
- Modify: `docs/SOLUTION_POST_PURCHASE_AFTERCARE_MVP.md` (only if implementation details need a small update)

- [ ] **Step 1: Run focused backend verification**

Run: `bundle exec rspec spec/models/aftercare_dispatch_log_spec.rb spec/services/aftercare spec/jobs/aftercare spec/controllers/api/v1/accounts/aftercare spec/jobs/trigger_scheduled_items_job_spec.rb`
Expected: PASS.

- [ ] **Step 2: Run focused frontend verification**

Run: `pnpm vitest app/javascript/dashboard/routes/dashboard/aiControl/pages/specs/AiControlPanel.spec.js`
Expected: PASS.

- [ ] **Step 3: Run any required migration/schema verification**

Run: `bundle exec rails db:migrate RAILS_ENV=test`
Expected: PASS and schema updated.

- [ ] **Step 4: Summarize residual risks**

Explicitly call out anything not fully covered, especially:
- actual Meta opt-in/token semantics in production
- whether refresh-draft staleness threshold needs tuning
- whether operator pause should wait for a later phase

- [ ] **Step 5: Commit**

```bash
git add db/schema.rb docs/SOLUTION_POST_PURCHASE_AFTERCARE_MVP.md
git commit -m "docs: finalize aftercare phase 4 notes"
```
