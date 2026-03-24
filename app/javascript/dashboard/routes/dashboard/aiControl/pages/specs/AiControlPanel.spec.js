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
    listAftercareSequences: vi.fn(),
    getAftercareEligibility: vi.fn(),
    listAftercareEnrollments: vi.fn(),
    createAftercareEnrollment: vi.fn(),
    updateAftercareStepDraft: vi.fn(),
    regenerateAftercareDraft: vi.fn(),
    retryAftercareStep: vi.fn(),
    pauseAftercareEnrollment: vi.fn(),
    resumeAftercareEnrollment: vi.fn(),
    cancelAftercareEnrollment: vi.fn(),
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
    AiControlAPI.listAftercareSequences.mockResolvedValue({
      data: {
        payload: [
          {
            id: 1,
            code: 'post_purchase_checkin',
            name: 'Chăm sóc sau mua',
            default_timezone: 'Asia/Bangkok',
            steps: [
              {
                id: 11,
                position: 1,
                title: 'Hỏi thăm ngày 1',
                instructions: 'Hỏi thăm khách sau mua',
                offset_minutes: 1440,
                enabled: true,
              },
            ],
          },
        ],
      },
    });
    AiControlAPI.getAftercareEligibility.mockResolvedValue({
      data: {
        eligible: true,
        reason_code: 'eligible',
        channel_key: 'messenger',
      },
    });
    AiControlAPI.listAftercareEnrollments.mockResolvedValue({
      data: {
        payload: [
          {
            id: 91,
            status: 'pending_optin',
            contact: { name: 'Lan Nguyen' },
            conversation: { id: 101, display_id: 5001 },
            sequence: { name: 'Chăm sóc sau mua' },
            opt_in_subscription: { status: 'requested' },
            steps: [
              {
                id: 501,
                position: 1,
                status: 'scheduled',
                title: 'Hỏi thăm ngày 1',
                draft_status: 'ready',
                draft_body: 'Bản nháp cũ cho ngày 1.',
                draft_summary: 'Friendly day-1 check-in',
                scheduled_for: '2026-03-19T00:00:00Z',
                latest_dispatch_log: {
                  id: 801,
                  status: 'sent',
                  sent_at: '2026-03-18T01:00:00Z',
                },
                dispatch_logs: [
                  {
                    id: 801,
                    status: 'sent',
                    sent_at: '2026-03-18T01:00:00Z',
                  },
                ],
              },
              {
                id: 502,
                position: 2,
                status: 'failed',
                title: 'Hỏi thăm ngày 3',
                draft_status: 'ready',
                draft_body: 'Draft lỗi gửi ngày 3.',
                draft_summary: 'Retry candidate',
                scheduled_for: '2026-03-21T00:00:00Z',
                last_error: 'Graph API timeout',
                latest_dispatch_log: {
                  id: 802,
                  status: 'failed',
                  error_message: 'Graph API timeout',
                },
                dispatch_logs: [
                  {
                    id: 802,
                    status: 'failed',
                    error_message: 'Graph API timeout',
                  },
                ],
              },
            ],
          },
        ],
      },
    });
    AiControlAPI.createAftercareEnrollment.mockResolvedValue({
      data: {
        payload: {
          id: 92,
          status: 'pending_optin',
          contact: { name: 'Lan Nguyen' },
          conversation: { display_id: 5001 },
          sequence: { name: 'Chăm sóc sau mua' },
          opt_in_subscription: { status: 'not_requested' },
          steps: [{ scheduled_for: '2026-03-19T00:00:00Z' }],
        },
      },
    });
    AiControlAPI.regenerateAftercareDraft.mockResolvedValue({
      data: {
        payload: {
          id: 501,
          position: 1,
          title: 'Hỏi thăm ngày 1',
          draft_status: 'ready',
          draft_body: 'Bản nháp đã làm mới.',
          draft_summary: 'Updated friendly day-1 check-in',
          scheduled_for: '2026-03-19T00:00:00Z',
        },
      },
    });
    AiControlAPI.updateAftercareStepDraft.mockResolvedValue({
      data: {
        payload: {
          id: 501,
          position: 1,
          title: 'Hỏi thăm ngày 1',
          draft_status: 'ready',
          draft_body: 'Bản nháp đã sửa tay cho khách.',
          draft_summary: 'Friendly day-1 check-in',
          scheduled_for: '2026-03-19T00:00:00Z',
        },
      },
    });
    AiControlAPI.retryAftercareStep.mockResolvedValue({
      data: {
        payload: {
          id: 502,
          position: 2,
          status: 'scheduled',
          title: 'Hỏi thăm ngày 3',
          draft_status: 'ready',
          draft_body: 'Draft lỗi gửi ngày 3.',
          draft_summary: 'Retry candidate',
          scheduled_for: '2026-03-21T00:00:00Z',
          last_error: null,
        },
      },
    });
    AiControlAPI.pauseAftercareEnrollment.mockResolvedValue({
      data: {
        payload: {
          id: 91,
          status: 'paused',
          contact: { name: 'Lan Nguyen' },
          conversation: { id: 101, display_id: 5001 },
          sequence: { name: 'Chăm sóc sau mua' },
          opt_in_subscription: { status: 'requested' },
          steps: [
            {
              id: 501,
              position: 1,
              status: 'scheduled',
              title: 'Hỏi thăm ngày 1',
              draft_status: 'ready',
              draft_body: 'Bản nháp cũ cho ngày 1.',
              scheduled_for: '2026-03-19T00:00:00Z',
            },
            {
              id: 502,
              position: 2,
              status: 'failed',
              title: 'Hỏi thăm ngày 3',
              draft_status: 'ready',
              draft_body: 'Draft lỗi gửi ngày 3.',
              scheduled_for: '2026-03-21T00:00:00Z',
              last_error: 'Graph API timeout',
            },
          ],
        },
      },
    });
    AiControlAPI.resumeAftercareEnrollment.mockResolvedValue({
      data: {
        payload: {
          id: 91,
          status: 'active',
          contact: { name: 'Lan Nguyen' },
          conversation: { id: 101, display_id: 5001 },
          sequence: { name: 'Chăm sóc sau mua' },
          opt_in_subscription: { status: 'subscribed' },
          steps: [
            {
              id: 501,
              position: 1,
              status: 'scheduled',
              title: 'Hỏi thăm ngày 1',
              draft_status: 'ready',
              draft_body: 'Bản nháp cũ cho ngày 1.',
              scheduled_for: '2026-03-19T00:00:00Z',
            },
          ],
        },
      },
    });
    AiControlAPI.cancelAftercareEnrollment.mockResolvedValue({
      data: {
        payload: {
          id: 91,
          status: 'cancelled',
          contact: { name: 'Lan Nguyen' },
          conversation: { id: 101, display_id: 5001 },
          sequence: { name: 'Chăm sóc sau mua' },
          opt_in_subscription: { status: 'requested' },
          steps: [
            {
              id: 501,
              position: 1,
              status: 'cancelled',
              title: 'Hỏi thăm ngày 1',
              draft_status: 'ready',
              draft_body: 'Bản nháp cũ cho ngày 1.',
              scheduled_for: '2026-03-19T00:00:00Z',
            },
            {
              id: 502,
              position: 2,
              status: 'cancelled',
              title: 'Hỏi thăm ngày 3',
              draft_status: 'ready',
              draft_body: 'Draft lỗi gửi ngày 3.',
              scheduled_for: '2026-03-21T00:00:00Z',
            },
          ],
        },
      },
    });
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

  it('loads the aftercare tab with existing enrollments', async () => {
    const wrapper = createWrapper();

    await wrapper.find('[data-test-id="ai-control-tab-aftercare"]').trigger('click');
    await flushPromises();

    expect(AiControlAPI.listAftercareEnrollments).toHaveBeenCalled();
    expect(wrapper.text()).toContain('Lan Nguyen');
    expect(wrapper.text()).toContain('Chăm sóc sau mua');
    expect(wrapper.text()).toContain('Bản nháp cũ cho ngày 1.');
    expect(wrapper.text()).toContain('Gửi gần nhất');
  });

  it('regenerates an aftercare draft and updates the preview inline', async () => {
    const wrapper = createWrapper();

    await wrapper.find('[data-test-id="ai-control-tab-aftercare"]').trigger('click');
    await flushPromises();

    await wrapper
      .find('[data-test-id="aftercare-regenerate-91-501"]')
      .trigger('click');
    await flushPromises();

    expect(AiControlAPI.regenerateAftercareDraft).toHaveBeenCalledWith({
      enrollmentId: '91',
      stepId: '501',
    });
    expect(wrapper.text()).toContain('Bản nháp đã làm mới.');
  });

  it('allows editing an aftercare draft manually and saves the updated content inline', async () => {
    const wrapper = createWrapper();

    await wrapper.find('[data-test-id="ai-control-tab-aftercare"]').trigger('click');
    await flushPromises();

    await wrapper
      .find('[data-test-id="aftercare-edit-91-501"]')
      .trigger('click');
    await flushPromises();

    await wrapper
      .find('[data-test-id="aftercare-edit-input-91-501"]')
      .setValue('Bản nháp đã sửa tay cho khách.');
    await wrapper
      .find('[data-test-id="aftercare-edit-save-91-501"]')
      .trigger('click');
    await flushPromises();

    expect(AiControlAPI.updateAftercareStepDraft).toHaveBeenCalledWith({
      enrollmentId: '91',
      stepId: '501',
      draftBody: 'Bản nháp đã sửa tay cho khách.',
    });
    expect(wrapper.text()).toContain('Bản nháp đã sửa tay cho khách.');
  });

  it('retries a failed aftercare step and updates the step state inline', async () => {
    const wrapper = createWrapper();

    await wrapper.find('[data-test-id="ai-control-tab-aftercare"]').trigger('click');
    await flushPromises();

    await wrapper
      .find('[data-test-id="aftercare-retry-91-502"]')
      .trigger('click');
    await flushPromises();

    expect(AiControlAPI.retryAftercareStep).toHaveBeenCalledWith({
      enrollmentId: '91',
      stepId: '502',
    });
    expect(
      wrapper.vm.aftercareEnrollments[0].steps.find(step => step.id === 502).status
    ).toBe('scheduled');
  });

  it('cancels an enrollment from the aftercare tab and updates the status inline', async () => {
    const wrapper = createWrapper();

    await wrapper.find('[data-test-id="ai-control-tab-aftercare"]').trigger('click');
    await flushPromises();

    await wrapper
      .find('[data-test-id="aftercare-cancel-91"]')
      .trigger('click');
    await flushPromises();

    expect(AiControlAPI.cancelAftercareEnrollment).toHaveBeenCalledWith({
      enrollmentId: '91',
    });
    expect(wrapper.vm.aftercareEnrollments[0].status).toBe('cancelled');
  });

  it('pauses an active enrollment from the aftercare tab and updates the status inline', async () => {
    AiControlAPI.listAftercareEnrollments.mockResolvedValueOnce({
      data: {
        payload: [
          {
            id: 91,
            status: 'active',
            contact: { name: 'Lan Nguyen' },
            conversation: { id: 101, display_id: 5001 },
            sequence: { name: 'Chăm sóc sau mua' },
            opt_in_subscription: { status: 'subscribed' },
            steps: [
              {
                id: 501,
                position: 1,
                status: 'scheduled',
                title: 'Hỏi thăm ngày 1',
                draft_status: 'ready',
                draft_body: 'Bản nháp cũ cho ngày 1.',
                scheduled_for: '2026-03-19T00:00:00Z',
              },
            ],
          },
        ],
      },
    });

    const wrapper = createWrapper();

    await wrapper.find('[data-test-id="ai-control-tab-aftercare"]').trigger('click');
    await flushPromises();

    await wrapper
      .find('[data-test-id="aftercare-pause-91"]')
      .trigger('click');
    await flushPromises();

    expect(AiControlAPI.pauseAftercareEnrollment).toHaveBeenCalledWith({
      enrollmentId: '91',
    });
    expect(wrapper.vm.aftercareEnrollments[0].status).toBe('paused');
  });

  it('resumes a paused enrollment from the aftercare tab and updates the status inline', async () => {
    AiControlAPI.listAftercareEnrollments.mockResolvedValueOnce({
      data: {
        payload: [
          {
            id: 91,
            status: 'paused',
            contact: { name: 'Lan Nguyen' },
            conversation: { id: 101, display_id: 5001 },
            sequence: { name: 'Chăm sóc sau mua' },
            opt_in_subscription: { status: 'subscribed' },
            steps: [
              {
                id: 501,
                position: 1,
                status: 'scheduled',
                title: 'Hỏi thăm ngày 1',
                draft_status: 'ready',
                draft_body: 'Bản nháp cũ cho ngày 1.',
                scheduled_for: '2026-03-19T00:00:00Z',
              },
            ],
          },
        ],
      },
    });

    const wrapper = createWrapper();

    await wrapper.find('[data-test-id="ai-control-tab-aftercare"]').trigger('click');
    await flushPromises();

    await wrapper
      .find('[data-test-id="aftercare-resume-91"]')
      .trigger('click');
    await flushPromises();

    expect(AiControlAPI.resumeAftercareEnrollment).toHaveBeenCalledWith({
      enrollmentId: '91',
    });
    expect(wrapper.vm.aftercareEnrollments[0].status).toBe('active');
  });

  it('opens the aftercare dialog for the selected conversation and submits a new enrollment', async () => {
    const wrapper = createWrapper();

    wrapper.vm.localAiControlConversationId = 101;
    wrapper.vm.customer360 = {
      contact_profile: {
        name: 'Lan Nguyen',
        email: 'lan.nguyen@example.com',
      },
      conversation: { display_id: 5001 },
    };
    await nextTick();

    await wrapper.find('[data-test-id="aftercare-open-dialog"]').trigger('click');
    await flushPromises();

    expect(AiControlAPI.listAftercareSequences).toHaveBeenCalled();
    expect(AiControlAPI.getAftercareEligibility).toHaveBeenCalledWith({
      conversationId: '101',
    });

    await wrapper
      .find('[data-test-id="aftercare-note-input"]')
      .setValue('Khách vừa mua gói cơ bản');
    await wrapper
      .find('[data-test-id="aftercare-contact-email-input"]')
      .setValue('lan.aftercare@example.com');
    await wrapper
      .find('[data-test-id="aftercare-anchor-input"]')
      .setValue('2026-03-19T10:00');
    await wrapper.find('[data-test-id="aftercare-submit"]').trigger('click');
    await flushPromises();

    expect(AiControlAPI.createAftercareEnrollment).toHaveBeenCalledWith(
      expect.objectContaining({
        conversationId: '101',
        sequenceId: 1,
        staffNote: 'Khách vừa mua gói cơ bản',
        contactEmail: 'lan.aftercare@example.com',
      })
    );
  });

  it('surfaces Gmail readiness warnings in the aftercare tab', async () => {
    AiControlAPI.listAftercareEnrollments.mockResolvedValueOnce({
      data: {
        payload: [
          {
            id: 91,
            status: 'blocked_capability_disabled',
            contact: { name: 'Lan Nguyen' },
            conversation: { id: 101, display_id: 5001 },
            sequence: { name: 'Chăm sóc sau mua' },
            opt_in_subscription: {
              status: 'unsupported_channel_capability',
              capability_status: 'smtp_not_configured',
            },
            steps: [],
          },
        ],
      },
    });

    const wrapper = createWrapper();

    await wrapper.find('[data-test-id="ai-control-tab-aftercare"]').trigger('click');
    await flushPromises();

    expect(wrapper.text()).toContain('Gmail: SMTP/Gmail chưa cấu hình.');
    expect(wrapper.text()).toContain('Gmail chưa sẵn sàng');
  });

  it('renders long aftercare draft previews on a single line', async () => {
    const longDraft = [
      'Khách vừa mua khóa nên cần nhắn lời chào mừng và nhắc kiểm tra email kích hoạt.',
      'Đồng thời gợi ý phản hồi nếu khách chưa thấy tài liệu trong hộp thư.',
    ].join('\n');

    AiControlAPI.listAftercareEnrollments.mockResolvedValueOnce({
      data: {
        payload: [
          {
            id: 91,
            status: 'pending_optin',
            contact: { name: 'Lan Nguyen' },
            conversation: { id: 101, display_id: 5001 },
            sequence: { name: 'Chăm sóc sau mua' },
            opt_in_subscription: { status: 'requested' },
            steps: [
              {
                id: 501,
                position: 1,
                status: 'scheduled',
                title: 'Hỏi thăm ngày 1',
                draft_status: 'ready',
                draft_body: longDraft,
                scheduled_for: '2026-03-19T00:00:00Z',
              },
            ],
          },
        ],
      },
    });

    const wrapper = createWrapper();

    await wrapper.find('[data-test-id="ai-control-tab-aftercare"]').trigger('click');
    await flushPromises();

    const preview = wrapper.find('[data-test-id="aftercare-draft-preview-91-501"]');

    expect(preview.attributes('title')).toBe(longDraft);
    expect(preview.text()).toContain('Khách vừa mua khóa');
    expect(preview.text()).toContain('...');
    expect(preview.text()).not.toContain(
      'Đồng thời gợi ý phản hồi nếu khách chưa thấy tài liệu trong hộp thư.'
    );
  });

  it('keeps the user in the aftercare tab when clicking the draft preview', async () => {
    const wrapper = createWrapper();

    await wrapper.find('[data-test-id="ai-control-tab-aftercare"]').trigger('click');
    await flushPromises();

    await wrapper
      .find('[data-test-id="aftercare-draft-preview-91-501"]')
      .trigger('click');
    await flushPromises();

    expect(wrapper.vm.activeMainTab).toBe('aftercare');
    expect(mockRouter.push).not.toHaveBeenCalled();
  });
});
