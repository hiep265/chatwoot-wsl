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

  reviewPaymentCase(caseId, {
    reviewAction,
    reviewedBy,
    reviewNote,
    data,
    triggerPostPaymentSkill = true,
  } = {}) {
    return axios.post(`${this.url}/payment_review_cases/${caseId}/review`, {
      review_action: reviewAction,
      reviewed_by: reviewedBy,
      review_note: reviewNote,
      data,
      trigger_post_payment_skill: triggerPostPaymentSkill,
    });
  }

  getBlockedInboxes() {
    return axios.get(`${this.url}/blocked_inboxes`);
  }

  blockInbox(inboxId) {
    return axios.post(`${this.url}/blocked_inboxes`, { inbox_id: String(inboxId) });
  }

  unblockInbox(inboxId) {
    return axios.delete(`${this.url}/blocked_inboxes`, { data: { inbox_id: String(inboxId) } });
  }

  toggleAllInboxes(inboxIds, actionType) {
    return axios.post(`${this.url}/blocked_inboxes/toggle_all`, {
      inbox_ids: inboxIds.map(String),
      action_type: actionType,
    });
  }
}

export default new AiControlAPI();
