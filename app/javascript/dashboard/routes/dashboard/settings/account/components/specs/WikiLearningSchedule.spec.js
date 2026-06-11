import { flushPromises, mount } from '@vue/test-utils';

import WikiLearningSchedule from '../WikiLearningSchedule.vue';
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
    getWikiLearningSchedule: vi.fn(),
    updateWikiLearningSchedule: vi.fn(),
    runWikiLearningNow: vi.fn(),
  },
}));

const global = {
  stubs: {
    SectionLayout: {
      template: '<section><slot /><slot name="headerActions" /></section>',
    },
    Switch: {
      props: ['modelValue'],
      template:
        '<input data-testid="wiki-enabled" type="checkbox" :checked="modelValue" @change="$emit(`update:modelValue`, $event.target.checked)" />',
    },
    NextInput: {
      inheritAttrs: false,
      props: ['modelValue'],
      template:
        '<input v-bind="$attrs" :value="modelValue" @input="$emit(\'update:modelValue\', $event.target.value)" />',
    },
    NextButton: {
      inheritAttrs: false,
      template:
        '<button v-bind="$attrs" @click="$emit(\'click\')"><slot /></button>',
    },
  },
};

describe('WikiLearningSchedule', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    AiControlAPI.getWikiLearningSchedule.mockResolvedValue({
      data: {
        enabled: true,
        time_of_day: '04:30',
        timezone_name: 'Asia/Seoul',
      },
    });
    AiControlAPI.updateWikiLearningSchedule.mockResolvedValue({
      data: {
        enabled: false,
        time_of_day: '05:00',
        timezone_name: 'UTC',
      },
    });
    AiControlAPI.runWikiLearningNow.mockResolvedValue({
      data: {
        schedule: {
          enabled: true,
          time_of_day: '04:30',
          timezone_name: 'Asia/Seoul',
        },
      },
    });
  });

  it('loads the current wiki schedule on mount', async () => {
    const wrapper = mount(WikiLearningSchedule, { global });

    await flushPromises();

    expect(AiControlAPI.getWikiLearningSchedule).toHaveBeenCalled();
    expect(wrapper.find('[data-testid="wiki-enabled"]').element.checked).toBe(
      true
    );
  });

  it('saves the updated wiki schedule', async () => {
    const wrapper = mount(WikiLearningSchedule, { global });

    await flushPromises();
    await wrapper.find('[data-testid="wiki-enabled"]').setValue(false);
    await wrapper.find('[data-testid="wiki-time"]').setValue('05:00');
    await wrapper.find('[data-testid="wiki-timezone"]').setValue('UTC');
    await wrapper.find('[data-testid="wiki-save"]').trigger('click');
    await flushPromises();

    expect(AiControlAPI.updateWikiLearningSchedule).toHaveBeenCalledWith({
      enabled: false,
      timeOfDay: '05:00',
      timezoneName: 'UTC',
    });
    expect(alertMock).toHaveBeenCalledWith(
      'GENERAL_SETTINGS.FORM.WIKI_LEARNING.API.SUCCESS'
    );
  });
});
