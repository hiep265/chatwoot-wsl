import { vi } from 'vitest';

function mockComponent(name) {
  return { default: { name } };
}

vi.mock('./Wrapper.vue', () => mockComponent('SettingsContent'));
vi.mock('./Index.vue', () => mockComponent('Index'));
vi.mock('./MfaSettings.vue', () => mockComponent('MfaSettings'));

import profile from './profile.routes';

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

describe('profile routes', () => {
  it('loads profile pages lazily', () => {
    expectLazyComponents(profile.routes);
  });
});
