import { vi } from 'vitest';

function mockComponent(name) {
  return { default: { name } };
}

vi.mock('./pages/ContactsIndex.vue', () => mockComponent('ContactsIndex'));
vi.mock('./pages/ContactManageView.vue', () =>
  mockComponent('ContactManageView')
);

import { routes } from './routes';

describe('contacts routes', () => {
  it('loads contact pages lazily', () => {
    routes.forEach(route => {
      expect(typeof route.component).toBe('function');
      route.children.forEach(child => {
        expect(typeof child.component).toBe('function');
      });
    });
  });
});
