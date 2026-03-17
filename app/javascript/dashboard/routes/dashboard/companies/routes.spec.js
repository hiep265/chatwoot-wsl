import { vi } from 'vitest';

function mockComponent(name) {
  return { default: { name } };
}

vi.mock('./pages/CompaniesIndex.vue', () => mockComponent('CompaniesIndex'));

import { routes } from './routes';

describe('companies routes', () => {
  it('loads company pages lazily', () => {
    routes.forEach(route => {
      expect(typeof route.component).toBe('function');
      route.children.forEach(child => {
        expect(typeof child.component).toBe('function');
      });
    });
  });
});
