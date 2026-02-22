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
}

export default new AiControlAPI();
