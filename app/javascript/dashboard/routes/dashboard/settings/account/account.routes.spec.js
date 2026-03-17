import { vi } from 'vitest';

function mockComponent(name) {
  return { default: { name } };
}

vi.mock('./Index.vue', () => mockComponent('Index'));
vi.mock('../SettingsWrapper.vue', () => mockComponent('SettingsWrapper'));

import account from './account.routes';

describe('account routes', () => {
  it('loads account pages lazily', () => {
    account.routes.forEach(route => {
      expect(typeof route.component).toBe('function');
      route.children.forEach(child => {
        expect(typeof child.component).toBe('function');
      });
    });
  });
});
