import { vi } from 'vitest';

function mockComponent(name) {
  return { default: { name } };
}

vi.mock('../SettingsWrapper.vue', () => mockComponent('SettingsWrapper'));
vi.mock('./Index.vue', () => mockComponent('AttributesHome'));

import attributes from './attributes.routes';

describe('attribute routes', () => {
  it('loads attribute pages lazily', () => {
    attributes.routes.forEach(route => {
      expect(typeof route.component).toBe('function');
      route.children
        .filter(child => !child.redirect)
        .forEach(child => {
          expect(typeof child.component).toBe('function');
        });
    });
  });
});
