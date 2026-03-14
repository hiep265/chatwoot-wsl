import { computed } from 'vue';
import {
  useFunctionGetter,
  useMapGetter,
  useStore,
} from 'dashboard/composables/store.js';
import { useAccount } from 'dashboard/composables/useAccount';
import { useAlert } from 'dashboard/composables';
import { useI18n } from 'vue-i18n';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import TasksAPI from 'dashboard/api/captain/tasks';

export function useCaptain() {
  const store = useStore();
  const { t } = useI18n();
  const { currentAccount, isCloudFeatureEnabled } = useAccount();
  const currentChat = useMapGetter('getSelectedChat');
  const replyMode = useMapGetter('draftMessages/getReplyEditorMode');
  const accountUIFlags = useMapGetter('accounts/getUIFlags');
  const conversationId = computed(() => currentChat.value?.id);
  const draftKey = computed(
    () => `draft-${conversationId.value}-${replyMode.value}`
  );
  const draftMessage = useFunctionGetter('draftMessages/get', draftKey);

  const normalizeCaptainLimit = limit => {
    if (!limit) return null;

    return {
      totalCount: Number(limit.total_count ?? limit.totalCount ?? 0),
      currentAvailable: Number(
        limit.current_available ?? limit.currentAvailable ?? 0
      ),
      consumed: Number(limit.consumed ?? 0),
    };
  };

  const captainLimits = computed(() => {
    const rawCaptainLimits = currentAccount.value?.limits?.captain;
    if (!rawCaptainLimits) return null;

    return {
      documents: normalizeCaptainLimit(rawCaptainLimits.documents),
      responses: normalizeCaptainLimit(rawCaptainLimits.responses),
    };
  });

  const documentLimits = computed(() => captainLimits.value?.documents || null);
  const responseLimits = computed(() => captainLimits.value?.responses || null);
  const isFetchingLimits = computed(
    () => accountUIFlags.value?.isFetchingLimits || false
  );

  // === Feature Flags ===
  const captainEnabled = computed(() => {
    // All features are now free - always enable captain
    return true;
  });

  const captainTasksEnabled = computed(() => {
    return isCloudFeatureEnabled(FEATURE_FLAGS.CAPTAIN_TASKS);
  });

  // === Error Handling ===
  /**
   * Handles API errors and displays appropriate error messages.
   * Silently returns for aborted requests.
   * @param {Error} error - The error object from the API call.
   */
  const handleAPIError = error => {
    if (error.name === 'AbortError' || error.name === 'CanceledError') {
      return;
    }
    const errorMessage =
      error.response?.data?.error ||
      t('INTEGRATION_SETTINGS.OPEN_AI.GENERATE_ERROR');
    useAlert(errorMessage);
  };

  // === Task Methods ===
  /**
   * Rewrites content with a specific operation.
   * @param {string} content - The content to rewrite.
   * @param {string} operation - The operation (fix_spelling_grammar, casual, professional, expand, shorten, improve, etc).
   * @param {Object} [options={}] - Additional options.
   * @param {AbortSignal} [options.signal] - AbortSignal to cancel the request.
   * @returns {Promise<{message: string, followUpContext?: Object}>} The rewritten content and optional follow-up context.
   */
  const rewriteContent = async (content, operation, options = {}) => {
    try {
      const result = await TasksAPI.rewrite(
        {
          content: content || draftMessage.value,
          operation,
          conversationId: conversationId.value,
        },
        options.signal
      );
      const {
        data: { message: generatedMessage, follow_up_context: followUpContext },
      } = result;
      return { message: generatedMessage, followUpContext };
    } catch (error) {
      handleAPIError(error);
      return { message: '' };
    }
  };

  /**
   * Summarizes a conversation.
   * @param {Object} [options={}] - Additional options.
   * @param {AbortSignal} [options.signal] - AbortSignal to cancel the request.
   * @returns {Promise<{message: string, followUpContext?: Object}>} The summary and optional follow-up context.
   */
  const summarizeConversation = async (options = {}) => {
    try {
      const result = await TasksAPI.summarize(
        conversationId.value,
        options.signal
      );
      const {
        data: { message: generatedMessage, follow_up_context: followUpContext },
      } = result;
      return { message: generatedMessage, followUpContext };
    } catch (error) {
      handleAPIError(error);
      return { message: '' };
    }
  };

  /**
   * Gets a reply suggestion for the current conversation.
   * @param {Object} [options={}] - Additional options.
   * @param {AbortSignal} [options.signal] - AbortSignal to cancel the request.
   * @returns {Promise<{message: string, followUpContext?: Object}>} The reply suggestion and optional follow-up context.
   */
  const getReplySuggestion = async (options = {}) => {
    try {
      const result = await TasksAPI.replySuggestion(
        conversationId.value,
        options.signal
      );
      const {
        data: { message: generatedMessage, follow_up_context: followUpContext },
      } = result;
      return { message: generatedMessage, followUpContext };
    } catch (error) {
      handleAPIError(error);
      return { message: '' };
    }
  };

  /**
   * Sends a follow-up message to refine a previous AI task result.
   * @param {Object} options - The follow-up options.
   * @param {Object} options.followUpContext - The follow-up context from a previous task.
   * @param {string} options.message - The follow-up message/request from the user.
   * @param {AbortSignal} [options.signal] - AbortSignal to cancel the request.
   * @returns {Promise<{message: string, followUpContext: Object}>} The follow-up response and updated context.
   */
  const followUp = async ({ followUpContext, message, signal }) => {
    try {
      const result = await TasksAPI.followUp(
        { followUpContext, message, conversationId: conversationId.value },
        signal
      );
      const {
        data: { message: generatedMessage, follow_up_context: updatedContext },
      } = result;
      return { message: generatedMessage, followUpContext: updatedContext };
    } catch (error) {
      handleAPIError(error);
      return { message: '', followUpContext };
    }
  };

  /**
   * Processes an AI event. Routes to the appropriate method based on type.
   * @param {string} [type='improve'] - The type of AI event to process.
   * @param {string} [content=''] - The content to process.
   * @param {Object} [options={}] - Additional options.
   * @param {AbortSignal} [options.signal] - AbortSignal to cancel the request.
   * @returns {Promise<{message: string, followUpContext?: Object}>} The generated message and optional follow-up context.
   */
  const processEvent = async (type = 'improve', content = '', options = {}) => {
    if (type === 'summarize') {
      return summarizeConversation(options);
    }
    if (type === 'reply_suggestion') {
      return getReplySuggestion(options);
    }
    // All other types are rewrite operations
    return rewriteContent(content, type, options);
  };

  const fetchLimits = async () => {
    console.log('[Captain Limits] Bắt đầu luồng');
    console.log('[Captain Limits] Bước 1: Gửi yêu cầu tải giới hạn Captain');

    try {
      await store.dispatch('accounts/limits');

      if (captainLimits.value) {
        console.log('[Captain Limits] Bước 2: Đã nhận dữ liệu giới hạn Captain');
      } else {
        console.warn(
          '[Captain Limits] Cảnh báo tại bước 2: Chưa có dữ liệu giới hạn Captain'
        );
      }
    } catch (error) {
      console.error(
        '[Captain Limits] Lỗi tại bước 1: Không thể tải giới hạn Captain',
        error
      );
    } finally {
      console.log('[Captain Limits] Kết thúc luồng');
    }
  };

  return {
    // Feature flags
    captainEnabled,
    captainTasksEnabled,
    captainLimits,
    documentLimits,
    responseLimits,
    fetchLimits,
    isFetchingLimits,

    // Conversation context
    draftMessage,
    currentChat,

    // Task methods
    rewriteContent,
    summarizeConversation,
    getReplySuggestion,
    followUp,
    processEvent,
  };
}
