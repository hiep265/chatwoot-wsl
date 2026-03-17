import { vi } from 'vitest';

function mockComponent(name) {
  return { default: { name } };
}

vi.mock('../SettingsWrapper.vue', () => mockComponent('SettingsWrapper'));
vi.mock('./Index.vue', () => mockComponent('Index'));

import labels from './labels.routes';

describe('label routes', () => {
  it('loads label pages lazily', () => {
    labels.routes.forEach(route => {
      expect(typeof route.component).toBe('function');
      route.children
        .filter(child => !child.redirect)
        .forEach(child => {
          expect(typeof child.component).toBe('function');
        });
    });
  });
});
