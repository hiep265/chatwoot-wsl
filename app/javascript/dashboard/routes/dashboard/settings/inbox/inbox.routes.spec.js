import { vi } from 'vitest';

function mockComponent(name) {
  return { default: { name } };
}

vi.mock('./ChannelFactory.vue', () => mockComponent('ChannelFactory'));
vi.mock('../Wrapper.vue', () => mockComponent('SettingsContent'));
vi.mock('../SettingsWrapper.vue', () => mockComponent('SettingsWrapper'));
vi.mock('./Index.vue', () => mockComponent('InboxHome'));
vi.mock('./Settings.vue', () => mockComponent('Settings'));
vi.mock('./InboxChannels.vue', () => mockComponent('InboxChannel'));
vi.mock('./ChannelList.vue', () => mockComponent('ChannelList'));
vi.mock('./AddAgents.vue', () => mockComponent('AddAgents'));
vi.mock('./FinishSetup.vue', () => mockComponent('FinishSetup'));

import inboxRoutes from './inbox.routes';

const expectLazyComponents = routes => {
  routes.forEach(route => {
    if (route.component) {
      expect(typeof route.component).toBe('function');
    }

    if (route.children) {
      expectLazyComponents(route.children);
    }
  });
};

describe('settings inbox routes', () => {
  it('loads inbox pages lazily', () => {
    expectLazyComponents(inboxRoutes.routes);
  });
});
