import { flushPromises, mount } from '@vue/test-utils';

import ChatwootReplyReplay from '../ChatwootReplyReplay.vue';
import AiControlAPI from 'dashboard/api/aiControl';

const alertMock = vi.fn();

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: key => key,
  }),
}));

vi.mock('dashboard/composables', () => ({
  useAlert: (...args) => alertMock(...args),
}));

vi.mock('dashboard/api/aiControl', () => ({
  default: {
    getChatwootReplyReplayConfig: vi.fn(),
    updateChatwootReplyReplayConfig: vi.fn(),
  },
}));

const global = {
  stubs: {
    SectionLayout: {
      template: '<section><slot name="headerActions" /><slot /></section>',
    },
    Switch: {
      props: ['modelValue'],
      template:
        '<input data-testid="toggle" type="checkbox" :checked="modelValue" @change="$emit(`update:modelValue`, $event.target.checked); $emit(`change`, $event.target.checked)" />',
    },
  },
};

describe('ChatwootReplyReplay', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    AiControlAPI.getChatwootReplyReplayConfig.mockResolvedValue({
      data: {
        enabled: true,
        replay_after_minutes: 60,
        active_window_hours: 24,
      },
    });
    AiControlAPI.updateChatwootReplyReplayConfig.mockResolvedValue({
      data: {
        enabled: false,
        replay_after_minutes: 60,
        active_window_hours: 24,
      },
    });
  });

  it('loads the saved replay configuration on mount', async () => {
    const wrapper = mount(ChatwootReplyReplay, { global });

    await flushPromises();

    expect(AiControlAPI.getChatwootReplyReplayConfig).toHaveBeenCalled();
    expect(wrapper.find('[data-testid="toggle"]').element.checked).toBe(true);
  });

  it('updates the replay toggle when the switch changes', async () => {
    const wrapper = mount(ChatwootReplyReplay, { global });

    await flushPromises();
    await wrapper.find('[data-testid="toggle"]').setValue(false);
    await flushPromises();

    expect(AiControlAPI.updateChatwootReplyReplayConfig).toHaveBeenCalledWith({
      enabled: false,
    });
    expect(alertMock).toHaveBeenCalledWith(
      'GENERAL_SETTINGS.FORM.CHATWOOT_REPLY_REPLAY.API.SUCCESS'
    );
  });
});
