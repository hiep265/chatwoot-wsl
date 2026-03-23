# Aftercare Sequences Phase 3 Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the Aftercare Phase 3 draft generation lane so Chatwoot can generate, store, preview, and regenerate AI drafts through `chatbotlevan` and a dedicated Kimi aftercare drafter agent.

**Architecture:** Extend `chatwoot-wsl` with persistent draft fields, generation jobs, regenerate APIs, and UI preview controls. Add one internal `chatbotlevan` endpoint plus a focused service that runs a dedicated `aftercare_drafter` Kimi agent and returns strict JSON. Keep Chatwoot as the only source of truth for step drafts and versions.

**Tech Stack:** Ruby on Rails, Sidekiq, Vue 3, Vitest, FastAPI, Python 3.12, Kimi CLI agent specs.

---

### Task 1: Add failing Chatwoot specs for draft persistence and regenerate flow

**Files:**
- Create: `spec/controllers/api/v1/accounts/aftercare/enrollment_steps_controller_spec.rb`
- Create: `spec/services/aftercare/generate_step_draft_service_spec.rb`
- Create: `spec/jobs/aftercare/generate_step_draft_job_spec.rb`
- Modify: `spec/controllers/api/v1/accounts/aftercare/enrollments_controller_spec.rb`

- [ ] **Step 1: Write the failing request/service/job specs**
- [ ] **Step 2: Run targeted RSpec commands and confirm they fail because draft fields, service, job, and route do not exist yet**
- [ ] **Step 3: Cover success and failure paths, including regenerate and persisted preview payloads**

### Task 2: Add Chatwoot schema and model support for draft storage

**Files:**
- Create: `db/migrate/20260318140000_add_draft_fields_to_aftercare_enrollment_steps.rb`
- Modify: `app/models/aftercare_enrollment_step.rb`
- Modify: `app/models/aftercare_enrollment.rb`

- [ ] **Step 1: Write the migration for draft columns**
- [ ] **Step 2: Update step/enrollment JSON serializers to expose preview fields**
- [ ] **Step 3: Run the relevant specs and confirm the schema/model layer turns the red tests green**

### Task 3: Implement Chatwoot draft generation service, job, and regenerate endpoint

**Files:**
- Create: `app/services/aftercare/generate_step_draft_service.rb`
- Create: `app/jobs/aftercare/generate_step_draft_job.rb`
- Create: `app/controllers/api/v1/accounts/aftercare/enrollment_steps_controller.rb`
- Modify: `app/services/aftercare/create_enrollment_service.rb`
- Modify: `config/routes.rb`

- [ ] **Step 1: Write minimal code for the generation service that builds payloads, calls `chatbotlevan`, and persists results**
- [ ] **Step 2: Add the Sidekiq job and enqueue it for enabled steps after enrollment creation**
- [ ] **Step 3: Add the regenerate endpoint for one step**
- [ ] **Step 4: Record audit events for draft generated and draft failed states**
- [ ] **Step 5: Run targeted backend specs until all pass**

### Task 4: Add failing frontend tests and implement aftercare draft preview/regenerate UI

**Files:**
- Create: `app/javascript/dashboard/routes/dashboard/aiControl/pages/AftercareEnrollmentDialog.spec.js`
- Modify: `app/javascript/dashboard/api/aiControl.js`
- Modify: `app/javascript/dashboard/routes/dashboard/aiControl/pages/AiControlPanel.vue`

- [ ] **Step 1: Write failing frontend coverage for preview and regenerate behavior**
- [ ] **Step 2: Add API client support for regenerate**
- [ ] **Step 3: Render draft preview, draft status, and regenerate controls in the Aftercare tab**
- [ ] **Step 4: Run the targeted Vitest command and confirm the UI tests pass**

### Task 5: Add failing chatbotlevan tests for the internal aftercare draft endpoint

**Files:**
- Create: `tests/unit/test_aftercare_draft_service.py`
- Create: `tests/integration/test_aftercare_draft_routes.py`

- [ ] **Step 1: Write failing Python tests for request validation, message trimming, successful draft parsing, and malformed JSON handling**
- [ ] **Step 2: Run the targeted pytest command and confirm the route/service are missing**

### Task 6: Implement chatbotlevan aftercare draft service and route

**Files:**
- Create: `src/application/services/aftercare_draft_service.py`
- Create: `src/interfaces/http/aftercare_routes.py`
- Modify: `src/main.py`
- Modify: `src/interfaces/http/chatwoot_routes.py`

- [ ] **Step 1: Add a dedicated `aftercare_drafter` Kimi manager factory or resolver in the existing Chatwoot route helpers**
- [ ] **Step 2: Implement the service that shapes payloads, caps recent messages at 30, runs the agent, and parses JSON**
- [ ] **Step 3: Add the internal HTTP endpoint and mount its router**
- [ ] **Step 4: Run the targeted pytest suite until green**

### Task 7: Add the dedicated Kimi aftercare drafter agent

**Files:**
- Create: `src/kimi_cli/agents/aftercare_drafter/agent.yaml`
- Create: `src/kimi_cli/agents/aftercare_drafter/system.md`
- Modify: `src/kimi_cli/agentspec.py`

- [ ] **Step 1: Add a minimal internal-only agent spec with no customer-facing tools**
- [ ] **Step 2: Write the system prompt with strict JSON-only output contract**
- [ ] **Step 3: Wire the agent constant into `agentspec.py` so `chatbotlevan` can resolve it cleanly**

### Task 8: Verify end-to-end targeted suites

**Files:**
- Test: `spec/controllers/api/v1/accounts/aftercare/enrollments_controller_spec.rb`
- Test: `spec/controllers/api/v1/accounts/aftercare/enrollment_steps_controller_spec.rb`
- Test: `spec/services/aftercare/generate_step_draft_service_spec.rb`
- Test: `spec/jobs/aftercare/generate_step_draft_job_spec.rb`
- Test: `tests/unit/test_aftercare_draft_service.py`
- Test: `tests/integration/test_aftercare_draft_routes.py`

- [ ] **Step 1: Run the targeted Rails spec commands**
- [ ] **Step 2: Run the targeted Python pytest commands**
- [ ] **Step 3: Run the targeted frontend test command if available**
- [ ] **Step 4: Summarize anything still blocked or deferred**
