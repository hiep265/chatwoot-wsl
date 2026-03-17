import { vi } from 'vitest';

function mockComponent(name) {
  return { default: { name } };
}

vi.mock('../SettingsWrapper.vue', () => mockComponent('SettingsWrapper'));
vi.mock('./Index.vue', () => mockComponent('Index'));

import security from './security.routes';

describe('security routes', () => {
  it('loads security pages lazily', () => {
    security.routes.forEach(route => {
      expect(typeof route.component).toBe('function');
      route.children.forEach(child => {
        expect(typeof child.component).toBe('function');
      });
    });
  });
});
