import { vi } from 'vitest';

function mockComponent(name) {
  return { default: { name } };
}

vi.mock('../SettingsWrapper.vue', () => mockComponent('SettingsWrapper'));
vi.mock('./Index.vue', () => mockComponent('Automation'));

import automation from './automation.routes';

describe('automation routes', () => {
  it('loads automation pages lazily', () => {
    automation.routes.forEach(route => {
      expect(typeof route.component).toBe('function');
      route.children
        .filter(child => !child.redirect)
        .forEach(child => {
          expect(typeof child.component).toBe('function');
        });
    });
  });
});
