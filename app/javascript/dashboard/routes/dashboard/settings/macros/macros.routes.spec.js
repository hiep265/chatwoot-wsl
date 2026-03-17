import { vi } from 'vitest';

function mockComponent(name) {
  return { default: { name } };
}

vi.mock('../Wrapper.vue', () => mockComponent('SettingsContent'));
vi.mock('../SettingsWrapper.vue', () => mockComponent('SettingsWrapper'));
vi.mock('./Index.vue', () => mockComponent('Macros'));
vi.mock('./MacroEditor.vue', () => mockComponent('MacroEditor'));

import macros from './macros.routes';

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

describe('macro routes', () => {
  it('loads macro pages lazily', () => {
    expectLazyComponents(macros.routes);
  });
});
