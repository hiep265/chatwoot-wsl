import { mount } from '@vue/test-utils';
import { createStore } from 'vuex';

import ConversationView from '../ConversationView.vue';

vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({
    accountId: '1',
  }),
}));

vi.mock('shared/helpers/mitt', () => ({
  emitter: {
    emit: vi.fn(),
  },
}));

const createWrapper = ({ forceTwoPane = false } = {}) => {
  const store = createStore({
    state: {
      route: {},
    },
    getters: {
      getAllConversations: () => [{ id: 101 }],
      getSelectedChat: () => ({ id: 101 }),
      getUISettings: () => ({
        conversation_display_type: 'expanded',
        is_contact_sidebar_open: false,
      }),
    },
  });

  vi.spyOn(store, 'dispatch').mockResolvedValue();

  return mount(ConversationView, {
    props: {
      inboxId: 0,
      conversationId: 101,
      forceTwoPane,
    },
    global: {
      plugins: [store],
      mocks: {
        $route: {
          query: {},
        },
      },
      stubs: {
        ChatList: {
          props: ['showConversationList', 'isOnExpandedLayout'],
          template:
            '<div data-test-id="chat-list" :data-show-conversation-list="String(showConversationList)" :data-expanded="String(isOnExpandedLayout)" />',
        },
        ConversationBox: {
          props: ['isOnExpandedLayout'],
          template:
            '<div data-test-id="conversation-box" :data-expanded="String(isOnExpandedLayout)"><slot /></div>',
        },
        CmdBarConversationSnooze: {
          template: '<div data-test-id="cmd-bar" />',
        },
        SidepanelSwitch: {
          template: '<div data-test-id="sidepanel-switch" />',
        },
        ConversationSidebar: {
          template: '<div data-test-id="conversation-sidebar" />',
        },
      },
    },
  });
};

describe('ConversationView', () => {
  it('hides the chat list in expanded mode when a conversation is selected', () => {
    const wrapper = createWrapper();

    expect(
      wrapper
        .find('[data-test-id="chat-list"]')
        .attributes('data-show-conversation-list')
    ).toBe('false');
    expect(
      wrapper
        .find('[data-test-id="conversation-box"]')
        .attributes('data-expanded')
    ).toBe('true');
  });

  it('keeps the chat list visible when forceTwoPane is enabled', () => {
    const wrapper = createWrapper({ forceTwoPane: true });

    expect(
      wrapper
        .find('[data-test-id="chat-list"]')
        .attributes('data-show-conversation-list')
    ).toBe('true');
    expect(
      wrapper
        .find('[data-test-id="conversation-box"]')
        .attributes('data-expanded')
    ).toBe('false');
  });
});
