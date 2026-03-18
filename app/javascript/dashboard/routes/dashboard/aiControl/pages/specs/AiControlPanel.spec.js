import { flushPromises, mount } from '@vue/test-utils';
import { nextTick, reactive } from 'vue';
import { createStore } from 'vuex';

import AiControlPanel from '../AiControlPanel.vue';
import ReportsAPI from 'dashboard/api/reports';
import SummaryReportsAPI from 'dashboard/api/summaryReports';
import InboxConversationAPI from 'dashboard/api/inbox/conversation';
import AiControlAPI from 'dashboard/api/aiControl';

const mockRoute = reactive({
  name: 'ai_control_panel',
  params: { accountId: '1' },
  query: {},
});

const mockRouter = {
  push: vi.fn(),
};

vi.mock('vue-router', async () => {
  const actual = await vi.importActual('vue-router');
  return {
    ...actual,
    useRoute: () => mockRoute,
    useRouter: () => mockRouter,
  };
});

vi.mock('dashboard/api/reports', () => ({
  default: {
    getReports: vi.fn(),
    getSummary: vi.fn(),
    getBotMetrics: vi.fn(),
  },
}));

vi.mock('dashboard/api/summaryReports', () => ({
  default: {
    getLabelReports: vi.fn(),
  },
}));

vi.mock('dashboard/api/inbox/conversation', () => ({
  default: {
    get: vi.fn(),
  },
}));

vi.mock('dashboard/api/aiControl', () => ({
  default: {
    getManagerAiHandoffQueue: vi.fn(),
    listPaymentReviewCases: vi.fn(),
    getBlockedInboxes: vi.fn(),
    getManagerCustomer360: vi.fn(),
  },
}));

vi.mock('dashboard/composables', () => ({
  useAlert: vi.fn(),
}));

vi.mock('shared/helpers/mitt', () => ({
  emitter: {
    on: vi.fn(),
    off: vi.fn(),
    emit: vi.fn(),
  },
}));

const createWrapper = ({ labels = [] } = {}) => {
  const store = createStore({
    getters: {
      'labels/getLabels': () => labels,
      'inboxes/getInboxes': () => [],
    },
    actions: {},
  });

  vi.spyOn(store, 'dispatch').mockResolvedValue();

  return mount(AiControlPanel, {
    global: {
      plugins: [store],
      stubs: {
        ReportHeader: {
          template: '<div><slot /></div>',
        },
        ReportFilterSelector: true,
        ConversationView: {
          props: ['conversationId'],
          template:
            '<div data-test-id="conversation-view">{{ conversationId }}</div>',
        },
        Button: {
          props: ['label'],
          emits: ['click'],
          template: '<button @click="$emit(\'click\')">{{ label }}</button>',
        },
        Avatar: {
          props: ['name'],
          template: '<div class="avatar">{{ name }}</div>',
        },
        AddLabel: true,
        CommentThread: true,
        'router-link': {
          template: '<a><slot /></a>',
        },
        'woot-modal': {
          props: ['show'],
          emits: ['update:show'],
          template: '<div v-if="show"><slot /></div>',
        },
        'woot-delete-modal': true,
      },
    },
  });
};

describe('AiControlPanel', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    vi.useFakeTimers();
    vi.setSystemTime(new Date('2026-03-18T00:00:00Z'));
    window.Chart = vi.fn(() => ({ destroy: vi.fn() }));
    Element.prototype.scrollIntoView = vi.fn();

    ReportsAPI.getReports.mockResolvedValue([]);
    ReportsAPI.getSummary.mockResolvedValue({ data: {} });
    ReportsAPI.getBotMetrics.mockResolvedValue({
      data: { conversation_count: 0, message_count: 0 },
    });
    SummaryReportsAPI.getLabelReports.mockResolvedValue({ data: [] });
    InboxConversationAPI.get.mockImplementation(({ labels } = {}) => {
      if (Array.isArray(labels) && labels.length) {
        return Promise.resolve({
          data: {
            data: {
              payload: [
                {
                  id: 101,
                  display_id: 5001,
                  status: 'open',
                  meta: {
                    sender: {
                      name: 'Lan Nguyen',
                      thumbnail: 'https://example.com/lan.png',
                    },
                  },
                },
              ],
            },
          },
        });
      }

      return Promise.resolve({
        data: {
          data: {
            payload: [],
          },
        },
      });
    });
    AiControlAPI.getManagerAiHandoffQueue.mockResolvedValue({
      data: { items: [] },
    });
    AiControlAPI.listPaymentReviewCases.mockResolvedValue({
      data: { cases: [], total: 0 },
    });
    AiControlAPI.getBlockedInboxes.mockResolvedValue({
      data: { blocked_inbox_ids: [] },
    });
    AiControlAPI.getManagerCustomer360.mockResolvedValue({ data: null });
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  it('opens a label popup instead of navigating away from the current page', async () => {
    const wrapper = createWrapper();

    wrapper.vm.labelSummary = [
      { name: 'khách_mới', conversationsCount: 1 },
    ];
    await nextTick();

    await wrapper.find('[data-test-id="ai-control-tab-reporting"]').trigger('click');
    await flushPromises();
    await wrapper
      .find('[data-test-id="report-label-trigger-khach_moi"]')
      .trigger('click');
    await flushPromises();

    expect(mockRouter.push).not.toHaveBeenCalled();
    expect(InboxConversationAPI.get).toHaveBeenCalledWith(
      expect.objectContaining({
        labels: ['khách_mới'],
      })
    );
    expect(wrapper.text()).toContain('Lan Nguyen');
  });

  it('opens the selected conversation inside the current AI Control page', async () => {
    const wrapper = createWrapper();

    wrapper.vm.labelSummary = [
      { name: 'khách_mới', conversationsCount: 1 },
    ];
    await nextTick();

    await wrapper.find('[data-test-id="ai-control-tab-reporting"]').trigger('click');
    await flushPromises();
    await wrapper
      .find('[data-test-id="report-label-trigger-khach_moi"]')
      .trigger('click');
    await flushPromises();

    await wrapper
      .find('[data-test-id="report-label-conversation-101"]')
      .trigger('click');
    await flushPromises();

    expect(mockRouter.push).not.toHaveBeenCalled();
    expect(wrapper.vm.activeMainTab).toBe('operations');
    expect(String(wrapper.vm.aiControlConversationId)).toBe('101');
    expect(wrapper.find('[data-test-id="conversation-view"]').text()).toContain(
      '101'
    );
  });

  it('loads the reporting chart with metric tabs inside the previous AI trend card', async () => {
    const wrapper = createWrapper();

    await wrapper.find('[data-test-id="ai-control-tab-reporting"]').trigger('click');
    await flushPromises();

    expect(wrapper.text()).toContain('Doanh thu');
    expect(wrapper.text()).toContain('Khách mới');
    expect(wrapper.text()).toContain('Tỉ lệ chốt');
    expect(wrapper.text()).toContain('Khách quay lại');
    expect(window.Chart).toHaveBeenCalled();
  });

  it('switches the reporting chart to the new clients metric', async () => {
    SummaryReportsAPI.getLabelReports.mockResolvedValue({ data: [] });

    const wrapper = createWrapper();

    await wrapper.find('[data-test-id="ai-control-tab-reporting"]').trigger('click');
    await flushPromises();
    SummaryReportsAPI.getLabelReports.mockClear();

    await wrapper.find('[data-test-id="trend-metric-new_clients"]').trigger('click');
    await flushPromises();

    expect(SummaryReportsAPI.getLabelReports).toHaveBeenNthCalledWith(1, {
      since: 1766016000,
      until: 1766534400,
      businessHours: false,
    });
  });

  it('updates the close rate chart range when selecting a different stock-style window', async () => {
    SummaryReportsAPI.getLabelReports.mockResolvedValue({ data: [] });
    ReportsAPI.getSummary.mockResolvedValue({ data: { conversations_count: 0 } });

    const wrapper = createWrapper();

    await wrapper.find('[data-test-id="ai-control-tab-reporting"]').trigger('click');
    await flushPromises();

    await wrapper.find('[data-test-id="trend-metric-close_rate"]').trigger('click');
    await flushPromises();
    SummaryReportsAPI.getLabelReports.mockClear();
    ReportsAPI.getSummary.mockClear();

    await wrapper.find('[data-test-id="ai-growth-range-1y"]').trigger('click');
    await flushPromises();

    expect(SummaryReportsAPI.getLabelReports).toHaveBeenNthCalledWith(1, {
      since: 1743465600,
      until: 1745971200,
      businessHours: false,
    });
    expect(ReportsAPI.getSummary).toHaveBeenNthCalledWith(
      1,
      1743465600,
      1745971200,
      'account',
      undefined,
      undefined,
      false
    );
  });
});
