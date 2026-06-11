import { defineComponent, h, ref } from 'vue';
import { flushPromises, mount } from '@vue/test-utils';

import AiControlAPI from 'dashboard/api/aiControl';
import BotAnswerFeedback from '../BotAnswerFeedback.vue';
import { MESSAGE_TYPES } from '../constants';
import { provideMessageContext } from '../provider';

const testState = vi.hoisted(() => ({
  dispatch: vi.fn(() => Promise.resolve()),
  alert: vi.fn(),
  learnFromWrongAnswer: vi.fn(() => Promise.resolve()),
  selectedChat: {
    messages: [
      {
        id: 76,
        content: 'Khach hoi khoa AI cho nguoi moi',
        message_type: 0,
        created_at: 1,
      },
      {
        id: 77,
        content: 'Bot tra loi sai',
        message_type: 1,
        created_at: 2,
        content_attributes: { is_bot_generated: true },
      },
    ],
  },
  assistants: [{ id: 3, name: 'Sales Bot' }],
}));

vi.mock('dashboard/api/aiControl', () => ({
  default: {
    learnFromWrongAnswer: testState.learnFromWrongAnswer,
  },
}));

vi.mock('dashboard/composables', () => ({
  useAlert: testState.alert,
}));

vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch: testState.dispatch }),
  useMapGetter: key => ({
    get value() {
      if (key === 'getSelectedChat') return testState.selectedChat;
      if (key === 'captainAssistants/getRecords') return testState.assistants;
      if (key === 'getSelectedChatAttachments') return [];
      return null;
    },
  }),
}));

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
}));

const ButtonStub = defineComponent({
  emits: ['click'],
  setup(_, { emit }) {
    return () =>
      h(
        'button',
        {
          'data-testid': 'open-feedback',
          onClick: () => emit('click'),
        },
        'open'
      );
  },
});

const DialogStub = defineComponent({
  emits: ['confirm', 'close'],
  setup(_, { emit, slots, expose }) {
    expose({
      open: vi.fn(),
      close: vi.fn(),
    });

    return () =>
      h('div', { 'data-testid': 'feedback-dialog' }, [
        slots.default?.(),
        h(
          'button',
          {
            'data-testid': 'confirm-feedback',
            onClick: () => emit('confirm'),
          },
          'confirm'
        ),
      ]);
  },
});

const ComboBoxStub = defineComponent({
  inheritAttrs: false,
  props: {
    modelValue: {
      type: String,
      default: '',
    },
  },
  emits: ['update:modelValue'],
  setup(props, { emit }) {
    return () =>
      h('select', {
        'data-testid': 'assistant-select',
        value: props.modelValue,
        onChange: event => emit('update:modelValue', event.target.value),
      });
  },
});

const TextAreaStub = defineComponent({
  props: {
    modelValue: {
      type: String,
      default: '',
    },
  },
  emits: ['update:modelValue'],
  setup(props, { emit }) {
    return () =>
      h('textarea', {
        'data-testid': 'feedback-note',
        value: props.modelValue,
        onInput: event => emit('update:modelValue', event.target.value),
      });
  },
});

const mountFeedback = () => {
  const Harness = defineComponent({
    components: { BotAnswerFeedback },
    setup() {
      provideMessageContext({
        id: ref(77),
        content: ref('Bot tra loi sai'),
        contentAttributes: ref({ is_bot_generated: true }),
        sender: ref({ id: 3 }),
        messageType: ref(MESSAGE_TYPES.OUTGOING),
        conversationId: ref(129),
      });
      return {};
    },
    template: '<BotAnswerFeedback />',
  });

  return mount(Harness, {
    global: {
      stubs: {
        Button: ButtonStub,
        Dialog: DialogStub,
        ComboBox: ComboBoxStub,
        TextArea: TextAreaStub,
      },
      mocks: {
        $t: key => key,
      },
    },
  });
};

describe('BotAnswerFeedback', () => {
  beforeEach(() => {
    testState.dispatch.mockClear();
    testState.alert.mockClear();
    testState.learnFromWrongAnswer.mockClear();
  });

  it('creates the pending FAQ audit and triggers instant wiki learning for the marked bot answer', async () => {
    const wrapper = mountFeedback();

    await wrapper.get('[data-testid="open-feedback"]').trigger('click');
    await wrapper.get('[data-testid="feedback-note"]').setValue('Bot noi sai ve khoa AI');
    await wrapper.get('[data-testid="confirm-feedback"]').trigger('click');
    await flushPromises();

    expect(testState.dispatch).toHaveBeenCalledWith(
      'captainResponses/create',
      expect.objectContaining({
        conversation_id: 129,
        question: 'Khach hoi khoa AI cho nguoi moi',
        status: 'pending',
      })
    );
    expect(AiControlAPI.learnFromWrongAnswer).toHaveBeenCalledWith({
      conversationId: 129,
      botMessageId: 77,
      reviewerNote: 'Bot noi sai ve khoa AI',
    });
  });
});
