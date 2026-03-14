import { useCaptain } from '../useCaptain';
import {
  useFunctionGetter,
  useMapGetter,
  useStore,
} from 'dashboard/composables/store';
import { useAccount } from 'dashboard/composables/useAccount';
import { useConfig } from 'dashboard/composables/useConfig';
import { useI18n } from 'vue-i18n';
import TasksAPI from 'dashboard/api/captain/tasks';

vi.mock('dashboard/composables/store');
vi.mock('dashboard/composables/useAccount');
vi.mock('dashboard/composables/useConfig');
vi.mock('vue-i18n');
vi.mock('dashboard/api/captain/tasks');
vi.mock('dashboard/helper/AnalyticsHelper/index', async importOriginal => {
  const actual = await importOriginal();
  actual.default = {
    track: vi.fn(),
  };
  return actual;
});
vi.mock('dashboard/helper/AnalyticsHelper/events', () => ({
  CAPTAIN_EVENTS: {
    TEST_EVENT: 'captain_test_event',
  },
}));

describe('useCaptain', () => {
  const mockStore = {
    dispatch: vi.fn(),
  };
  const mockCaptainLimits = {
    documents: {
      total_count: 100,
      current_available: 40,
      consumed: 60,
    },
    responses: {
      total_count: 50,
      current_available: 10,
      consumed: 40,
    },
  };

  beforeEach(() => {
    vi.clearAllMocks();
    useStore.mockReturnValue(mockStore);
    useFunctionGetter.mockReturnValue({ value: 'Draft message' });
    useMapGetter.mockImplementation(getter => {
      const mockValues = {
        'accounts/getUIFlags': { isFetchingLimits: false },
        getSelectedChat: { id: '123' },
        'draftMessages/getReplyEditorMode': 'reply',
      };
      return { value: mockValues[getter] };
    });
    useI18n.mockReturnValue({ t: vi.fn() });
    useAccount.mockReturnValue({
      isCloudFeatureEnabled: vi.fn().mockReturnValue(true),
      currentAccount: {
        value: {
          limits: {
            captain: mockCaptainLimits,
          },
        },
      },
    });
    useConfig.mockReturnValue({
      isEnterprise: false,
    });
    mockStore.dispatch.mockResolvedValue();
  });

  it('initializes computed properties correctly', async () => {
    const {
      captainEnabled,
      captainTasksEnabled,
      captainLimits,
      documentLimits,
      responseLimits,
      isFetchingLimits,
      currentChat,
      draftMessage,
    } = useCaptain();

    expect(captainEnabled.value).toBe(true);
    expect(captainTasksEnabled.value).toBe(true);
    expect(captainLimits.value).toEqual({
      documents: {
        totalCount: 100,
        currentAvailable: 40,
        consumed: 60,
      },
      responses: {
        totalCount: 50,
        currentAvailable: 10,
        consumed: 40,
      },
    });
    expect(documentLimits.value).toEqual({
      totalCount: 100,
      currentAvailable: 40,
      consumed: 60,
    });
    expect(responseLimits.value).toEqual({
      totalCount: 50,
      currentAvailable: 10,
      consumed: 40,
    });
    expect(isFetchingLimits.value).toBe(false);
    expect(currentChat.value).toEqual({ id: '123' });
    expect(draftMessage.value).toBe('Draft message');
  });

  it('uses_empty_limits_branch_when_captain_limits_missing', () => {
    useAccount.mockReturnValue({
      isCloudFeatureEnabled: vi.fn().mockReturnValue(true),
      currentAccount: { value: { limits: {} } },
    });

    const { captainLimits, documentLimits, responseLimits } = useCaptain();

    expect(captainLimits.value).toBe(null);
    expect(documentLimits.value).toBe(null);
    expect(responseLimits.value).toBe(null);
  });

  it('runs_full_limits_flow_when_dispatch_succeeds', async () => {
    const logSpy = vi.spyOn(console, 'log').mockImplementation(() => {});
    const warnSpy = vi.spyOn(console, 'warn').mockImplementation(() => {});
    const errorSpy = vi.spyOn(console, 'error').mockImplementation(() => {});
    const { fetchLimits } = useCaptain();

    await fetchLimits();

    expect(mockStore.dispatch).toHaveBeenCalledWith('accounts/limits');
    expect(logSpy.mock.calls).toEqual([
      ['[Captain Limits] Bắt đầu luồng'],
      ['[Captain Limits] Bước 1: Gửi yêu cầu tải giới hạn Captain'],
      ['[Captain Limits] Bước 2: Đã nhận dữ liệu giới hạn Captain'],
      ['[Captain Limits] Kết thúc luồng'],
    ]);
    expect(warnSpy).not.toHaveBeenCalled();
    expect(errorSpy).not.toHaveBeenCalled();
  });

  it('uses_warning_branch_when_limits_flow_finishes_without_data', async () => {
    useAccount.mockReturnValue({
      isCloudFeatureEnabled: vi.fn().mockReturnValue(true),
      currentAccount: { value: { limits: {} } },
    });
    const logSpy = vi.spyOn(console, 'log').mockImplementation(() => {});
    const warnSpy = vi.spyOn(console, 'warn').mockImplementation(() => {});
    const errorSpy = vi.spyOn(console, 'error').mockImplementation(() => {});
    const { fetchLimits } = useCaptain();

    await fetchLimits();

    expect(mockStore.dispatch).toHaveBeenCalledWith('accounts/limits');
    expect(warnSpy).toHaveBeenCalledWith(
      '[Captain Limits] Cảnh báo tại bước 2: Chưa có dữ liệu giới hạn Captain'
    );
    expect(logSpy).not.toHaveBeenCalledWith(
      '[Captain Limits] Bước 2: Đã nhận dữ liệu giới hạn Captain'
    );
    expect(errorSpy).not.toHaveBeenCalled();
  });

  it('stops_limits_flow_at_step_1_when_dispatch_fails', async () => {
    const requestError = new Error('network failed');
    const logSpy = vi.spyOn(console, 'log').mockImplementation(() => {});
    const errorSpy = vi.spyOn(console, 'error').mockImplementation(() => {});
    const warnSpy = vi.spyOn(console, 'warn').mockImplementation(() => {});
    mockStore.dispatch.mockRejectedValueOnce(requestError);
    const { fetchLimits } = useCaptain();

    await fetchLimits();

    expect(mockStore.dispatch).toHaveBeenCalledWith('accounts/limits');
    expect(errorSpy).toHaveBeenCalledWith(
      '[Captain Limits] Lỗi tại bước 1: Không thể tải giới hạn Captain',
      requestError
    );
    expect(logSpy).not.toHaveBeenCalledWith(
      '[Captain Limits] Bước 2: Đã nhận dữ liệu giới hạn Captain'
    );
    expect(warnSpy).not.toHaveBeenCalled();
    expect(logSpy).toHaveBeenLastCalledWith('[Captain Limits] Kết thúc luồng');
  });

  it('rewrites content', async () => {
    TasksAPI.rewrite.mockResolvedValue({
      data: { message: 'Rewritten content', follow_up_context: { id: 'ctx1' } },
    });

    const { rewriteContent } = useCaptain();
    const result = await rewriteContent('Original content', 'improve', {});

    expect(TasksAPI.rewrite).toHaveBeenCalledWith(
      {
        content: 'Original content',
        operation: 'improve',
        conversationId: '123',
      },
      undefined
    );
    expect(result).toEqual({
      message: 'Rewritten content',
      followUpContext: { id: 'ctx1' },
    });
  });

  it('summarizes conversation', async () => {
    TasksAPI.summarize.mockResolvedValue({
      data: { message: 'Summary', follow_up_context: { id: 'ctx2' } },
    });

    const { summarizeConversation } = useCaptain();
    const result = await summarizeConversation({});

    expect(TasksAPI.summarize).toHaveBeenCalledWith('123', undefined);
    expect(result).toEqual({
      message: 'Summary',
      followUpContext: { id: 'ctx2' },
    });
  });

  it('gets reply suggestion', async () => {
    TasksAPI.replySuggestion.mockResolvedValue({
      data: { message: 'Reply suggestion', follow_up_context: { id: 'ctx3' } },
    });

    const { getReplySuggestion } = useCaptain();
    const result = await getReplySuggestion({});

    expect(TasksAPI.replySuggestion).toHaveBeenCalledWith('123', undefined);
    expect(result).toEqual({
      message: 'Reply suggestion',
      followUpContext: { id: 'ctx3' },
    });
  });

  it('sends follow-up message', async () => {
    TasksAPI.followUp.mockResolvedValue({
      data: {
        message: 'Follow-up response',
        follow_up_context: { id: 'ctx4' },
      },
    });

    const { followUp } = useCaptain();
    const result = await followUp({
      followUpContext: { id: 'ctx3' },
      message: 'Make it shorter',
    });

    expect(TasksAPI.followUp).toHaveBeenCalledWith(
      {
        followUpContext: { id: 'ctx3' },
        message: 'Make it shorter',
        conversationId: '123',
      },
      undefined
    );
    expect(result).toEqual({
      message: 'Follow-up response',
      followUpContext: { id: 'ctx4' },
    });
  });

  it('processes event and routes to correct method', async () => {
    TasksAPI.summarize.mockResolvedValue({
      data: { message: 'Summary' },
    });
    TasksAPI.replySuggestion.mockResolvedValue({
      data: { message: 'Reply' },
    });
    TasksAPI.rewrite.mockResolvedValue({
      data: { message: 'Rewritten' },
    });

    const { processEvent } = useCaptain();

    // Test summarize
    await processEvent('summarize', '', {});
    expect(TasksAPI.summarize).toHaveBeenCalled();

    // Test reply_suggestion
    await processEvent('reply_suggestion', '', {});
    expect(TasksAPI.replySuggestion).toHaveBeenCalled();

    // Test rewrite (improve)
    await processEvent('improve', 'content', {});
    expect(TasksAPI.rewrite).toHaveBeenCalled();
  });
});
