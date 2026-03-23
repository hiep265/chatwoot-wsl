/* global axios */
import ApiClient from './ApiClient';

class AiControlAPI extends ApiClient {
  constructor() {
    super('ai_control', { accountScoped: true });
  }

  trainFaq({
    days,
    dryRun = false,
    assistantName,
    maxConversations,
    perConversationLimit,
    conversationsPerBatch,
  } = {}) {
    return axios.post(`${this.url}/train_faq`, {
      days,
      dry_run: dryRun,
      assistant_name: assistantName,
      max_conversations: maxConversations,
      per_conversation_limit: perConversationLimit,
      conversations_per_batch: conversationsPerBatch,
    });
  }

  listPaymentReviewCases({
    reviewStatus = 'payment_review_pending',
    segment,
    limit = 50,
    offset = 0,
  } = {}) {
    const params = {
      review_status: reviewStatus,
      limit,
      offset,
    };

    if (segment) {
      params.segment = segment;
    }

    return axios.get(`${this.url}/payment_review_cases`, { params });
  }

  reviewPaymentCase(
    caseId,
    {
      reviewAction,
      reviewedBy,
      reviewNote,
      data,
      triggerPostPaymentSkill = true,
    } = {}
  ) {
    return axios.post(`${this.url}/payment_review_cases/${caseId}/review`, {
      review_action: reviewAction,
      reviewed_by: reviewedBy,
      review_note: reviewNote,
      data,
      trigger_post_payment_skill: triggerPostPaymentSkill,
    });
  }

  deletePaymentCase(caseId, { deletedBy } = {}) {
    return axios.delete(`${this.url}/payment_review_cases/${caseId}`, {
      params: {
        deleted_by: deletedBy,
      },
    });
  }

  getManagerDailyOverview({
    targetDate,
    timezoneName = 'Asia/Bangkok',
    limit = 12,
    maxConversations,
    maxMessagesPerConversation = 3,
  } = {}) {
    const params = {
      timezone_name: timezoneName,
      limit,
      max_messages_per_conversation: maxMessagesPerConversation,
    };
    if (targetDate) params.target_date = targetDate;
    if (maxConversations) params.max_conversations = maxConversations;
    return axios.get(`${this.url}/manager/daily_overview`, { params });
  }

  getManagerAiHandoffQueue({
    timezoneName = 'Asia/Bangkok',
    limit = 8,
    maxConversations,
  } = {}) {
    const params = { timezone_name: timezoneName, limit };
    if (maxConversations) params.max_conversations = maxConversations;
    return axios.get(`${this.url}/manager/ai_handoff_queue`, { params });
  }

  getManagerSlaRiskQueue({
    riskWindowMinutes = 30,
    limit = 6,
    maxConversations,
  } = {}) {
    const params = {
      risk_window_minutes: riskWindowMinutes,
      limit,
    };
    if (maxConversations) params.max_conversations = maxConversations;
    return axios.get(`${this.url}/manager/sla_risk_queue`, { params });
  }

  getManagerFollowUpDueQueue({
    staleAfterMinutes = 60,
    limit = 6,
    maxConversations,
  } = {}) {
    const params = {
      stale_after_minutes: staleAfterMinutes,
      limit,
    };
    if (maxConversations) params.max_conversations = maxConversations;
    return axios.get(`${this.url}/manager/follow_up_due_queue`, { params });
  }

  getManagerUnassignedHotQueue({
    minWaitingMinutes = 5,
    limit = 6,
    maxConversations,
  } = {}) {
    const params = {
      min_waiting_minutes: minWaitingMinutes,
      limit,
    };
    if (maxConversations) params.max_conversations = maxConversations;
    return axios.get(`${this.url}/manager/unassigned_hot_queue`, { params });
  }

  getManagerCustomer360({
    conversationId,
    contactId,
    recentMessageLimit = 8,
    memoryLimit = 5,
    memoryQuery,
  } = {}) {
    const params = {
      conversation_id: conversationId,
      recent_message_limit: recentMessageLimit,
      memory_limit: memoryLimit,
    };
    if (contactId) params.contact_id = contactId;
    if (memoryQuery) params.memory_query = memoryQuery;
    return axios.get(`${this.url}/manager/customer_360`, { params });
  }

  getManagerReplyGapWatch({
    minGapMinutes = 5,
    limit = 6,
    maxConversations,
  } = {}) {
    const params = {
      min_gap_minutes: minGapMinutes,
      limit,
    };
    if (maxConversations) params.max_conversations = maxConversations;
    return axios.get(`${this.url}/manager/reply_gap_watch`, { params });
  }

  getManagerPriorityDigest({
    limit = 10,
    maxConversations,
    riskWindowMinutes = 30,
    minWaitingMinutes = 5,
    staleAfterMinutes = 60,
    minGapMinutes = 5,
  } = {}) {
    const params = {
      limit,
      risk_window_minutes: riskWindowMinutes,
      min_waiting_minutes: minWaitingMinutes,
      stale_after_minutes: staleAfterMinutes,
      min_gap_minutes: minGapMinutes,
    };
    if (maxConversations) params.max_conversations = maxConversations;
    return axios.get(`${this.url}/manager/priority_digest`, { params });
  }

  getBlockedInboxes() {
    return axios.get(`${this.url}/blocked_inboxes`);
  }

  blockInbox(inboxId) {
    return axios.post(`${this.url}/blocked_inboxes`, {
      inbox_id: String(inboxId),
    });
  }

  unblockInbox(inboxId) {
    return axios.delete(`${this.url}/blocked_inboxes`, {
      data: { inbox_id: String(inboxId) },
    });
  }

  toggleAllInboxes(inboxIds, actionType) {
    return axios.post(`${this.url}/blocked_inboxes/toggle_all`, {
      inbox_ids: inboxIds.map(String),
      action_type: actionType,
    });
  }

  getCommentWebhookConfig() {
    return axios.get(`${this.url}/comment_webhook_config`);
  }

  updateCommentWebhookConfig({ commentWebhookUrl } = {}) {
    const payload = {
      comment_webhook_url: String(commentWebhookUrl || '').trim(),
    };
    return axios.put(`${this.url}/comment_webhook_config`, payload);
  }

  // ── Comment Tab ──

  listComments({ platform, status, inboxId, limit = 50, offset = 0 } = {}) {
    const params = { limit, offset };
    if (platform) params.platform = platform;
    if (status) params.status = status;
    if (inboxId) params.inbox_id = inboxId;
    return axios.get(`${this.url}/comments`, { params });
  }

  getCommentThread(conversationId) {
    return axios.get(`${this.url}/comments/${conversationId}/thread`);
  }

  replyComment(conversationId, { message }) {
    return axios.post(`${this.url}/comments/${conversationId}/reply`, {
      message,
    });
  }

  autoReplyComment(conversationId, { commentWebhookUrl } = {}) {
    const payload = {};
    if (commentWebhookUrl) {
      payload.comment_webhook_url = String(commentWebhookUrl).trim();
    }
    return axios.post(
      `${this.url}/comments/${conversationId}/auto_reply`,
      payload
    );
  }

  listAftercareSequences() {
    return axios.get(
      `${this.url.replace('/ai_control', '')}/aftercare/sequences`
    );
  }

  getAftercareEligibility({ conversationId } = {}) {
    return axios.get(
      `${this.url.replace('/ai_control', '')}/aftercare/eligibility`,
      {
        params: {
          conversation_id: String(conversationId || '').trim(),
        },
      }
    );
  }

  listAftercareEnrollments() {
    return axios.get(
      `${this.url.replace('/ai_control', '')}/aftercare/enrollments`
    );
  }

  createAftercareEnrollment({
    conversationId,
    sequenceId,
    contactEmail,
    staffNote,
    timezoneName,
    anchorAt,
    steps = [],
  } = {}) {
    return axios.post(
      `${this.url.replace('/ai_control', '')}/aftercare/enrollments`,
      {
        conversation_id: String(conversationId || '').trim(),
        sequence_id: sequenceId,
        contact_email: String(contactEmail || '').trim(),
        staff_note: staffNote,
        timezone_name: timezoneName,
        anchor_at: anchorAt,
        steps: steps.map(step => ({
          position: step.position,
          title: step.title,
          instructions: step.instructions,
          enabled: step.enabled,
          scheduled_for: step.scheduledFor,
          step_note: step.stepNote,
        })),
      }
    );
  }

  regenerateAftercareDraft({ enrollmentId, stepId } = {}) {
    return axios.post(
      `${this.url.replace('/ai_control', '')}/aftercare/enrollments/${enrollmentId}/steps/${stepId}/regenerate_draft`
    );
  }

  updateAftercareStepDraft({ enrollmentId, stepId, draftBody } = {}) {
    return axios.patch(
      `${this.url.replace('/ai_control', '')}/aftercare/enrollments/${enrollmentId}/steps/${stepId}`,
      {
        draft_body: String(draftBody || ''),
      }
    );
  }

  retryAftercareStep({ enrollmentId, stepId } = {}) {
    return axios.post(
      `${this.url.replace('/ai_control', '')}/aftercare/enrollments/${enrollmentId}/steps/${stepId}/retry`
    );
  }

  pauseAftercareEnrollment({ enrollmentId } = {}) {
    return axios.post(
      `${this.url.replace('/ai_control', '')}/aftercare/enrollments/${enrollmentId}/pause`
    );
  }

  resumeAftercareEnrollment({ enrollmentId } = {}) {
    return axios.post(
      `${this.url.replace('/ai_control', '')}/aftercare/enrollments/${enrollmentId}/resume`
    );
  }

  cancelAftercareEnrollment({ enrollmentId } = {}) {
    return axios.post(
      `${this.url.replace('/ai_control', '')}/aftercare/enrollments/${enrollmentId}/cancel`
    );
  }
}

export default new AiControlAPI();
