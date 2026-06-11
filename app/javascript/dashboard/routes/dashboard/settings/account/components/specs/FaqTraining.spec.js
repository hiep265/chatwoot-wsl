import { flushPromises, mount } from '@vue/test-utils';

import FaqTraining from '../FaqTraining.vue';
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
    trainFaq: vi.fn(),
  },
}));

const global = {
  stubs: {
    SectionLayout: {
      template: '<section><slot /></section>',
    },
    NextInput: {
      props: ['modelValue'],
      template:
        '<input data-testid="days-input" :value="modelValue" @input="$emit(`update:modelValue`, Number($event.target.value))" />',
    },
    NextButton: {
      template:
        '<button data-testid="run-training" @click="$emit(`click`)"><slot /></button>',
    },
  },
};

describe('FaqTraining', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    AiControlAPI.trainFaq.mockResolvedValue({
      data: {
        report: {
          published_count: 2,
          duplicate_count: 1,
          conflict_count: 0,
          error_count: 0,
        },
      },
    });
  });

  it('submits FAQ training with the selected day window', async () => {
    const wrapper = mount(FaqTraining, { global });

    await wrapper.find('[data-testid="days-input"]').setValue('14');
    await wrapper.find('[data-testid="run-training"]').trigger('click');
    await flushPromises();

    expect(AiControlAPI.trainFaq).toHaveBeenCalledWith({
      days: 14,
      dryRun: false,
      conversationsPerBatch: 20,
    });
    expect(alertMock).toHaveBeenCalled();
  });
});
