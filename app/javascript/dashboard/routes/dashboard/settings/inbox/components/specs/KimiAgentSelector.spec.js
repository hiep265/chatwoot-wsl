import { flushPromises, mount } from '@vue/test-utils';

import KimiAgentSelector from '../KimiAgentSelector.vue';
import AiControlAPI from 'dashboard/api/aiControl';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: key => key,
  }),
}));

vi.mock('dashboard/api/aiControl', () => ({
  default: {
    getChatwootAgents: vi.fn(),
  },
}));

describe('KimiAgentSelector', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    AiControlAPI.getChatwootAgents.mockResolvedValue({
      data: {
        agents: [
          {
            id: 'instagram_sales',
            name: 'Instagram Sales',
            chatwoot_message_compatible: true,
          },
          {
            id: 'wiki_reviewer',
            name: 'Wiki Reviewer',
            chatwoot_message_compatible: false,
          },
        ],
      },
    });
  });

  it('loads compatible agents and emits the selected agent id', async () => {
    const wrapper = mount(KimiAgentSelector, {
      props: {
        modelValue: '',
      },
    });

    await flushPromises();

    const optionTexts = wrapper.findAll('option').map(option => option.text());
    expect(optionTexts).toContain('Instagram Sales');
    expect(optionTexts).not.toContain('Wiki Reviewer');

    await wrapper.find('select').setValue('instagram_sales');

    expect(wrapper.emitted('update:modelValue')).toEqual([['instagram_sales']]);
  });
});
