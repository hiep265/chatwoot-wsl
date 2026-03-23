# Aftercare Sequences Phase 1-2 Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the first end-to-end Aftercare Sequences slice in Chatwoot with persistent templates, enrollment creation, eligibility checks, opt-in state tracking, and AiControlPanel UI.

**Architecture:** Add a dedicated `Aftercare` namespace in `chatwoot-wsl` for templates, enrollments, steps, subscriptions, audit events, services, and jobs. Keep Chatwoot as the sole source of truth and expose account-scoped APIs that the `AiControlPanel` consumes.

**Tech Stack:** Ruby on Rails, ActiveRecord, ActiveJob, Vue 3, Vuex, Vitest

---

### Task 1: Add backend tests for the aftercare domain

**Files:**
- Create: `spec/controllers/api/v1/accounts/aftercare/sequences_controller_spec.rb`
- Create: `spec/controllers/api/v1/accounts/aftercare/enrollments_controller_spec.rb`
- Create: `spec/controllers/api/v1/accounts/aftercare/eligibility_controller_spec.rb`
- Create: `spec/controllers/api/v1/accounts/aftercare/opt_in_events_controller_spec.rb`
- Create: `spec/services/aftercare/eligibility_service_spec.rb`

- [ ] Step 1: Write failing request and service specs for listing sequences, checking eligibility, creating enrollments, and ingesting opt-in events.
- [ ] Step 2: Run the targeted backend spec command and confirm the suite fails because the aftercare implementation does not exist yet.

### Task 2: Implement the aftercare schema and models

**Files:**
- Create: `db/migrate/20260318090000_create_aftercare_sequences.rb`
- Create: `app/models/aftercare_sequence.rb`
- Create: `app/models/aftercare_sequence_step.rb`
- Create: `app/models/aftercare_enrollment.rb`
- Create: `app/models/aftercare_enrollment_step.rb`
- Create: `app/models/aftercare_opt_in_subscription.rb`
- Create: `app/models/aftercare_audit_event.rb`
- Create: `spec/factories/aftercare_sequences.rb`
- Create: `spec/factories/aftercare_sequence_steps.rb`
- Create: `spec/factories/aftercare_enrollments.rb`
- Create: `spec/factories/aftercare_enrollment_steps.rb`
- Create: `spec/factories/aftercare_opt_in_subscriptions.rb`

- [ ] Step 1: Add the migration with seeded default sequence templates and steps.
- [ ] Step 2: Add the ActiveRecord models, enums, validations, and associations.
- [ ] Step 3: Add factories so controller and service specs can build aftercare records cleanly.

### Task 3: Implement services, job, controllers, and routes

**Files:**
- Modify: `config/routes.rb`
- Create: `app/services/aftercare/eligibility_service.rb`
- Create: `app/services/aftercare/audit_service.rb`
- Create: `app/services/aftercare/create_enrollment_service.rb`
- Create: `app/services/aftercare/opt_in_request_service.rb`
- Create: `app/services/aftercare/opt_in_webhook_ingest_service.rb`
- Create: `app/jobs/aftercare/request_opt_in_job.rb`
- Create: `app/controllers/api/v1/accounts/aftercare/sequences_controller.rb`
- Create: `app/controllers/api/v1/accounts/aftercare/eligibility_controller.rb`
- Create: `app/controllers/api/v1/accounts/aftercare/enrollments_controller.rb`
- Create: `app/controllers/api/v1/accounts/aftercare/opt_in_events_controller.rb`

- [ ] Step 1: Add routes for sequence listing, eligibility lookup, enrollment CRUD slice, and opt-in event ingestion.
- [ ] Step 2: Implement eligibility and enrollment services with transaction-safe cloning and audit events.
- [ ] Step 3: Implement the opt-in request job and webhook ingestion service.
- [ ] Step 4: Implement controllers that return stable JSON payloads for the UI.
- [ ] Step 5: Run the targeted backend spec command and make the new suite green.

### Task 4: Add frontend tests for the AiControlPanel aftercare flow

**Files:**
- Modify: `app/javascript/dashboard/routes/dashboard/aiControl/pages/specs/AiControlPanel.spec.js`

- [ ] Step 1: Add failing Vitest coverage for the aftercare tab and creation dialog behavior.
- [ ] Step 2: Run the targeted frontend test command and confirm the new assertions fail before UI code is added.

### Task 5: Implement the AiControlPanel aftercare UI

**Files:**
- Modify: `app/javascript/dashboard/api/aiControl.js`
- Modify: `app/javascript/dashboard/routes/dashboard/aiControl/pages/AiControlPanel.vue`
- Create: `app/javascript/dashboard/routes/dashboard/aiControl/pages/AftercareEnrollmentDialog.vue`

- [ ] Step 1: Add API client methods for sequences, eligibility, enrollment list/create, and opt-in events.
- [ ] Step 2: Add the new tab, list view, and dialog wiring in `AiControlPanel`.
- [ ] Step 3: Add the new dialog component with editable step overrides and eligibility feedback.
- [ ] Step 4: Run the targeted frontend test command and make the updated suite green.

### Task 6: Verify the integrated slice

**Files:**
- No new files

- [ ] Step 1: Run the targeted backend specs for the aftercare namespace.
- [ ] Step 2: Run the targeted frontend specs for `AiControlPanel`.
- [ ] Step 3: Report actual verification status with command results and any known gaps.
