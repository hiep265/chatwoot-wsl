import { shallowMount } from '@vue/test-utils';
import Message from '../Message.vue';
import { MESSAGE_TYPES, MESSAGE_STATUS } from '../constants';

vi.mock('dashboard/composables', () => ({
  useTrack: vi.fn(),
}));

vi.mock('shared/helpers/mitt', () => ({
  emitter: {
    on: vi.fn(),
    off: vi.fn(),
    emit: vi.fn(),
  },
}));

vi.mock('vue-router', async () => {
  const actual = await vi.importActual('vue-router');
  return {
    ...actual,
    useRoute: () => ({
      query: {},
    }),
  };
});

vi.mock('shared/helpers/localStorage', () => ({
  LocalStorage: {
    updateJsonStore: vi.fn(),
  },
}));

const buildProps = overrides => ({
  id: 42,
  messageType: MESSAGE_TYPES.SESSION_TRACE,
  status: MESSAGE_STATUS.SENT,
  attachments: [],
  content: 'agent trace debug block',
  contentAttributes: {
    traceType: 'kimi_context_message',
    contextMessage: {
      role: 'assistant',
      content: 'agent trace debug block',
    },
    source: {
      triggerMessageId: '999',
    },
  },
  conversationId: 7,
  createdAt: 1_712_345_678,
  currentUserId: 99,
  groupWithNext: true,
  private: true,
  ...overrides,
});

describe('Message', () => {
  it('renders session trace messages as centered trace bubbles without grouping avatars', () => {
    const wrapper = shallowMount(Message, {
      props: buildProps(),
    });

    expect(wrapper.find('trace-bubble-stub').exists()).toBe(true);
    expect(wrapper.find('[data-message-id="42"]').classes()).not.toContain(
      'group-with-next'
    );
    expect(wrapper.find('avatar-stub').exists()).toBe(false);
  });
});
