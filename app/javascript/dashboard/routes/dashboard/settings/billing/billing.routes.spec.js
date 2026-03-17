import { vi } from 'vitest';

function mockComponent(name) {
  return { default: { name } };
}

vi.mock('../SettingsWrapper.vue', () => mockComponent('SettingsWrapper'));
vi.mock('./Index.vue', () => mockComponent('Index'));

import billing from './billing.routes';

describe('billing routes', () => {
  it('loads billing pages lazily', () => {
    billing.routes.forEach(route => {
      expect(typeof route.component).toBe('function');
      route.children.forEach(child => {
        expect(typeof child.component).toBe('function');
      });
    });
  });
});
