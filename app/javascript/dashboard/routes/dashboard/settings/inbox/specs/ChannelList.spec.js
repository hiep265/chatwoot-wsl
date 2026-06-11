import { computed, defineComponent, h } from 'vue';
import { mount } from '@vue/test-utils';

import ChannelList from '../ChannelList.vue';

const mockRouterPush = vi.fn();

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: key => key,
  }),
}));

vi.mock('vue-router', () => ({
  useRouter: () => ({
    push: mockRouterPush,
  }),
}));

vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({
    accountId: computed(() => 1),
    currentAccount: computed(() => ({
      id: 1,
      features: {
        channel_tiktok: true,
      },
    })),
  }),
}));

vi.mock('dashboard/composables/store', () => ({
  useMapGetter: getterName => {
    if (getterName === 'globalConfig/get') {
      return computed(() => ({
        apiChannelName: '',
      }));
    }

    return computed(() => ({}));
  },
}));

const ChannelItemStub = defineComponent({
  name: 'ChannelItem',
  props: {
    channel: {
      type: Object,
      required: true,
    },
  },
  setup(props) {
    return () => h('div', { class: 'channel-item' }, props.channel.key);
  },
});

describe('ChannelList', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    window.chatwootConfig = {};
  });

  it('includes the TikTok channel even when TikTok app id is not configured', () => {
    const wrapper = mount(ChannelList, {
      global: {
        stubs: {
          ChannelItem: ChannelItemStub,
        },
      },
    });

    const channelKeys = wrapper
      .findAll('.channel-item')
      .map(channelItem => channelItem.text());

    expect(channelKeys).toContain('tiktok');
  });
});
