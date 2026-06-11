import { mount } from '@vue/test-utils';
import EditorModeToggle from '../EditorModeToggle.vue';
import { REPLY_EDITOR_MODES } from '../constants';

describe('EditorModeToggle', () => {
  const mountComponent = (props = {}) =>
    mount(EditorModeToggle, {
      props: {
        mode: REPLY_EDITOR_MODES.REPLY,
        ...props,
      },
      global: {
        mocks: {
          $t: key => key,
        },
      },
    });

  it('keeps the selected-mode chip from blocking segment clicks', () => {
    const wrapper = mountComponent();
    const selectedChip = wrapper.find('.absolute.shadow-sm');

    expect(selectedChip.exists()).toBe(true);
    expect(selectedChip.classes()).toContain('pointer-events-none');
  });

  it('only renders reply and private note inside the segmented toggle', () => {
    const wrapper = mountComponent();
    const buttons = wrapper.findAll('button');

    expect(buttons).toHaveLength(2);
    expect(wrapper.text()).not.toContain('CONVERSATION.REPLYBOX.AI_NOTE');
  });

  it('keeps private note clickable when replies are restricted', async () => {
    const wrapper = mountComponent({
      isReplyRestricted: true,
      mode: REPLY_EDITOR_MODES.NOTE,
    });
    const buttons = wrapper.findAll('button');

    expect(buttons[0].attributes('disabled')).toBeDefined();
    expect(buttons[1].attributes('disabled')).toBeUndefined();

    await buttons[1].trigger('click');

    expect(wrapper.emitted('setMode')).toEqual([[REPLY_EDITOR_MODES.NOTE]]);
  });
});
