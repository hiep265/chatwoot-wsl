import { vi } from 'vitest';

function mockComponent(name) {
  return { default: { name } };
}

vi.mock('./Index.vue', () => mockComponent('Bot'));
vi.mock('../SettingsWrapper.vue', () => mockComponent('SettingsWrapper'));

import agentBots from './agentBot.routes';

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

describe('agent bot routes', () => {
  it('loads agent bot pages lazily', () => {
    expectLazyComponents(agentBots.routes);
  });
});
