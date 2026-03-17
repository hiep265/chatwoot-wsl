import { vi } from 'vitest';

function mockComponent(name) {
  return { default: { name } };
}

vi.mock('../SettingsWrapper.vue', () => mockComponent('SettingsWrapper'));
vi.mock('./Index.vue', () => mockComponent('Index'));

import sla from './sla.routes';

describe('sla routes', () => {
  it('loads sla pages lazily', () => {
    sla.routes.forEach(route => {
      expect(typeof route.component).toBe('function');
      route.children
        .filter(child => !child.redirect)
        .forEach(child => {
          expect(typeof child.component).toBe('function');
        });
    });
  });
});
