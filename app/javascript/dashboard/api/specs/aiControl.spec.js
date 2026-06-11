import AiControlAPI from '../aiControl';
import ApiClient from '../ApiClient';

describe('#AiControlAPI', () => {
  it('creates correct instance', () => {
    expect(AiControlAPI).toBeInstanceOf(ApiClient);
    expect(AiControlAPI).toHaveProperty('getChatwootAgents');
  });

  describe('API calls', () => {
    const originalAxios = window.axios;
    const originalPath = window.location.pathname;
    const axiosMock = {
      get: vi.fn(() => Promise.resolve()),
      post: vi.fn(() => Promise.resolve()),
      put: vi.fn(() => Promise.resolve()),
    };

    beforeEach(() => {
      window.axios = axiosMock;
      window.history.pushState({}, '', '/app/accounts/5/settings/inboxes/list');
    });

    afterEach(() => {
      window.axios = originalAxios;
      window.history.pushState({}, '', originalPath);
    });

    it('#getChatwootAgents', () => {
      AiControlAPI.getChatwootAgents();

      expect(axiosMock.get).toHaveBeenCalledWith(
        '/api/v1/accounts/5/ai_control/chatwoot_agents'
      );
    });

    it('#getChatwootReplyReplayConfig', () => {
      AiControlAPI.getChatwootReplyReplayConfig();

      expect(axiosMock.get).toHaveBeenCalledWith(
        '/api/v1/accounts/5/ai_control/chatwoot_reply_replay_config'
      );
    });

    it('#updateChatwootReplyReplayConfig', () => {
      AiControlAPI.updateChatwootReplyReplayConfig({ enabled: true });

      expect(axiosMock.put).toHaveBeenCalledWith(
        '/api/v1/accounts/5/ai_control/chatwoot_reply_replay_config',
        { enabled: true }
      );
    });

    it('#learnFromWrongAnswer', () => {
      AiControlAPI.learnFromWrongAnswer({
        conversationId: 129,
        botMessageId: 77,
        reviewerNote: 'Bot noi sai ve khoa AI',
      });

      expect(axiosMock.post).toHaveBeenCalledWith(
        '/api/v1/accounts/5/ai_control/wiki_learning_wrong_answer',
        {
          conversation_id: 129,
          bot_message_id: 77,
          reviewer_note: 'Bot noi sai ve khoa AI',
        }
      );
    });
  });
});
