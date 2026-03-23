# Aftercare Phase 5 Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Complete Aftercare Phase 5 in Chatwoot so post-24h sends use Gmail instead of Meta recurring notifications, while staff can clearly see missing-email / SMTP-readiness problems.

**Architecture:** `chatwoot-wsl` stays the source of truth. Aftercare keeps the existing standard Messenger/Instagram lane inside the strict 24-hour window, but switches post-24h delivery to Gmail using Chatwoot mailer/SMTP readiness instead of Meta notification tokens. Existing outgoing Chatwoot messages remain the persistence point for aftercare dispatch, while social send services explicitly skip the `gmail` lane so only the dedicated aftercare mailer performs the send.

**Tech Stack:** Ruby on Rails, ActiveRecord, Sidekiq/ActiveJob, RSpec, existing Facebook Messenger gem, existing Instagram/Facebook send services, Vue 3.

> Updated implementation note: this plan was originally written for Meta recurring notifications. The current branch pivots phase 5 to Gmail delivery after `24h`.

---

### Task 1: Enforce the strict aftercare 24-hour gate

**Files:**
- Modify: `app/services/aftercare/eligibility_service.rb`
- Test: `spec/services/aftercare/eligibility_service_spec.rb`

- [ ] **Step 1: Write the failing eligibility spec**

Add a spec proving aftercare is blocked once the last incoming message is older than 24 hours even if the account has Meta human-agent extensions enabled.

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/services/aftercare/eligibility_service_spec.rb`
Expected: FAIL because the current service still inherits the longer human-agent window.

- [ ] **Step 3: Write minimal implementation**

Make `Aftercare::EligibilityService` compute a strict 24-hour aftercare window instead of reusing the broader human-agent reply window.

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/services/aftercare/eligibility_service_spec.rb`
Expected: PASS.

### Task 2: Send real Meta opt-in requests and store request audit data

**Files:**
- Modify: `app/services/aftercare/opt_in_request_service.rb`
- Modify: `app/models/aftercare_opt_in_subscription.rb`
- Test: `spec/services/aftercare/opt_in_request_service_spec.rb`

- [ ] **Step 1: Write the failing opt-in request specs**

Add specs for:
- successful Meta opt-in request posts a `notification_messages` template payload
- payload contains a stable aftercare mapping string for webhook correlation
- permission failure marks the subscription/enrollment as blocked with a clear reason
- authorization failure surfaces reauthorization required

- [ ] **Step 2: Run tests to verify they fail**

Run: `bundle exec rspec spec/services/aftercare/opt_in_request_service_spec.rb`
Expected: FAIL because the service currently only flips status locally.

- [ ] **Step 3: Write minimal implementation**

Rules:
- POST to the Meta messages endpoint with `template_type: notification_messages`
- embed account/conversation/enrollment/subscription/topic mapping into the opt-in payload
- store request time, clear stale errors, and record a full audit event
- translate capability/permission/auth failures into staff-visible state on the subscription and enrollment

- [ ] **Step 4: Run tests to verify they pass**

Run: `bundle exec rspec spec/services/aftercare/opt_in_request_service_spec.rb`
Expected: PASS.

### Task 3: Ingest real Meta opt-in webhooks from the existing webhook lanes

**Files:**
- Modify: `config/initializers/facebook_messenger.rb`
- Modify: `app/models/channel/facebook_page.rb`
- Create: `app/jobs/webhooks/facebook_opt_in_job.rb`
- Create: `app/services/aftercare/process_meta_opt_in_event_service.rb`
- Modify: `app/jobs/webhooks/instagram_events_job.rb`
- Test: `spec/jobs/webhooks/facebook_opt_in_job_spec.rb`
- Test: `spec/services/aftercare/process_meta_opt_in_event_service_spec.rb`

- [ ] **Step 1: Write the failing webhook specs**

Add specs proving:
- Facebook webhook `optin` events enqueue and resolve the correct subscription from the embedded payload
- subscribed/revoked/resumed events update token, expiry, and raw payload audit
- Instagram messaging entries with `optin` are accepted by the shared handler

- [ ] **Step 2: Run tests to verify they fail**

Run: `bundle exec rspec spec/jobs/webhooks/facebook_opt_in_job_spec.rb spec/services/aftercare/process_meta_opt_in_event_service_spec.rb`
Expected: FAIL because no webhook worker/service exists yet.

- [ ] **Step 3: Write minimal implementation**

Implementation rules:
- subscribe Facebook pages to `messaging_optins`
- register `Facebook::Messenger::Bot.on :optin`
- parse the embedded aftercare payload to find the subscription
- map Meta stop/resume/token fields onto existing aftercare subscription/enrollment states
- record raw webhook payload and token lifecycle audit data

- [ ] **Step 4: Run tests to verify they pass**

Run: `bundle exec rspec spec/jobs/webhooks/facebook_opt_in_job_spec.rb spec/services/aftercare/process_meta_opt_in_event_service_spec.rb`
Expected: PASS.

### Task 4: Split aftercare delivery lane between in-window and post-24h sends

**Files:**
- Modify: `app/services/aftercare/dispatch_step_service.rb`
- Modify: `app/services/facebook/send_on_facebook_service.rb`
- Modify: `app/services/instagram/base_send_service.rb`
- Test: `spec/services/aftercare/dispatch_step_service_spec.rb`
- Test: `spec/services/facebook/send_on_facebook_service_spec.rb`
- Test: `spec/services/instagram/send_on_instagram_service_spec.rb`
- Test: `spec/services/instagram/messenger/send_on_instagram_service_spec.rb`

- [ ] **Step 1: Write the failing dispatch/send specs**

Add specs for:
- within 24 hours, aftercare messages use the standard recipient lane
- outside 24 hours, aftercare messages use `notification_messages_token`
- expired or missing token blocks the step and surfaces the right enrollment/subscription state
- delivery metadata is stored for audit/debug

- [ ] **Step 2: Run tests to verify they fail**

Run: `bundle exec rspec spec/services/aftercare/dispatch_step_service_spec.rb spec/services/facebook/send_on_facebook_service_spec.rb spec/services/instagram/send_on_instagram_service_spec.rb spec/services/instagram/messenger/send_on_instagram_service_spec.rb`
Expected: FAIL because channel send services do not yet understand aftercare delivery metadata.

- [ ] **Step 3: Write minimal implementation**

Rules:
- determine lane from a strict 24-hour aftercare window, not the generic human-agent window
- standard lane keeps the normal recipient id
- marketing lane uses `recipient.notification_messages_token`
- outside 24 hours with invalid token/capability/auth must not fall back to a normal message send
- record the dispatch decision in audit and dispatch metadata

- [ ] **Step 4: Run tests to verify they pass**

Run: `bundle exec rspec spec/services/aftercare/dispatch_step_service_spec.rb spec/services/facebook/send_on_facebook_service_spec.rb spec/services/instagram/send_on_instagram_service_spec.rb spec/services/instagram/messenger/send_on_instagram_service_spec.rb`
Expected: PASS.

### Task 5: Surface permission/token/reauthorization issues in the aftercare operator UI

**Files:**
- Modify: `app/javascript/dashboard/routes/dashboard/aiControl/pages/AiControlPanel.vue`
- Modify: `app/javascript/dashboard/routes/dashboard/aiControl/pages/AftercareEnrollmentDialog.vue`
- Modify: `app/javascript/dashboard/routes/dashboard/aiControl/pages/specs/AiControlPanel.spec.js`

- [ ] **Step 1: Write the failing UI spec**

Add expectations that the aftercare tab/dialog surface:
- permission/capability missing
- token expired / re-opt-in needed
- inbox reauthorization required

- [ ] **Step 2: Run test to verify it fails**

Run: `pnpm vitest app/javascript/dashboard/routes/dashboard/aiControl/pages/specs/AiControlPanel.spec.js`
Expected: FAIL because the current UI only shows coarse status strings.

- [ ] **Step 3: Write minimal implementation**

Use existing aftercare payload plus the new subscription/enrollment error metadata to show compact warning text without redesigning the whole panel.

- [ ] **Step 4: Run test to verify it passes**

Run: `pnpm vitest app/javascript/dashboard/routes/dashboard/aiControl/pages/specs/AiControlPanel.spec.js`
Expected: PASS.

### Task 6: Verify focused Phase 5 behavior end to end

**Files:**
- Modify: `docs/SOLUTION_POST_PURCHASE_AFTERCARE_MVP.md` (only if small implementation notes need updating)

- [ ] **Step 1: Run focused backend verification**

Run: `bundle exec rspec spec/services/aftercare spec/jobs/webhooks/facebook_opt_in_job_spec.rb spec/services/facebook/send_on_facebook_service_spec.rb spec/services/instagram/send_on_instagram_service_spec.rb spec/services/instagram/messenger/send_on_instagram_service_spec.rb`
Expected: PASS.

- [ ] **Step 2: Run focused frontend verification**

Run: `pnpm vitest app/javascript/dashboard/routes/dashboard/aiControl/pages/specs/AiControlPanel.spec.js`
Expected: PASS.

- [ ] **Step 3: Summarize residual risks**

Call out anything still not fully exercised, especially:
- real Meta app permissions and webhook subscriptions in non-test environments
- exact Instagram marketing-message endpoint behavior if the connected channel is a pure `Channel::Instagram` login instead of a Facebook Page backed inbox
- migration-free reuse of existing aftercare states vs future need for more explicit blocked step states
