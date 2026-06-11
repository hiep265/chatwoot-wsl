import { mount } from '@vue/test-utils';
import ReplyTopPanel from '../ReplyTopPanel.vue';
import { REPLY_EDITOR_MODES } from '../constants';

vi.mock('dashboard/composables/useCaptain', () => ({
  useCaptain: () => ({
    captainTasksEnabled: false,
  }),
}));

vi.mock('dashboard/composables/useKeyboardEvents', () => ({
  useKeyboardEvents: vi.fn(),
}));

describe('ReplyTopPanel', () => {
  it('sets AI note mode from a separate AI note button', async () => {
    const wrapper = mount(ReplyTopPanel, {
      props: {
        mode: REPLY_EDITOR_MODES.REPLY,
      },
      global: {
        mocks: {
          $t: key => key,
        },
      },
    });

    const modeToggle = wrapper.findComponent({ name: 'EditorModeToggle' });
    expect(modeToggle.findAll('button')).toHaveLength(2);

    const aiNoteButton = wrapper.find('[data-test-id="ai-note-mode-button"]');
    expect(aiNoteButton.exists()).toBe(true);

    await aiNoteButton.trigger('click');

    expect(wrapper.emitted('setReplyMode')).toEqual([
      [REPLY_EDITOR_MODES.AI_NOTE],
    ]);
  });

  it('keeps the separate AI note button clickable when replies are restricted', async () => {
    const wrapper = mount(ReplyTopPanel, {
      props: {
        isReplyRestricted: true,
        mode: REPLY_EDITOR_MODES.NOTE,
      },
      global: {
        mocks: {
          $t: key => key,
        },
      },
    });

    const aiNoteButton = wrapper.find('[data-test-id="ai-note-mode-button"]');
    expect(aiNoteButton.attributes('disabled')).toBeUndefined();

    await aiNoteButton.trigger('click');

    expect(wrapper.emitted('setReplyMode')).toEqual([
      [REPLY_EDITOR_MODES.AI_NOTE],
    ]);
  });
});
