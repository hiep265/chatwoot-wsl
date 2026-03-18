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

const createWrapper = () => {
  const store = createStore({
    getters: {
      'labels/getLabels': () => [],
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
    window.Chart = vi.fn();
    Element.prototype.scrollIntoView = vi.fn();

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
});
