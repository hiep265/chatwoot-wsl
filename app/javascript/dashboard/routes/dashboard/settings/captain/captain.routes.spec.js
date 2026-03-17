import { vi } from 'vitest';

function mockComponent(name) {
  return { default: { name } };
}

vi.mock('../SettingsWrapper.vue', () => mockComponent('SettingsWrapper'));
vi.mock('./Index.vue', () => mockComponent('Index'));

import captain from './captain.routes';

describe('captain settings routes', () => {
  it('loads captain settings pages lazily', () => {
    captain.routes.forEach(route => {
      expect(typeof route.component).toBe('function');
      route.children.forEach(child => {
        expect(typeof child.component).toBe('function');
      });
    });
  });
});
