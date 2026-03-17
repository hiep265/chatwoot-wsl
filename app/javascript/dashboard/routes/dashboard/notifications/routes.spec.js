import { vi } from 'vitest';

function mockComponent(name) {
  return { default: { name } };
}

vi.mock('../settings/Wrapper.vue', () => mockComponent('SettingsWrapper'));
vi.mock('./components/NotificationsView.vue', () =>
  mockComponent('NotificationsView')
);

import { routes } from './routes';

describe('notification routes', () => {
  it('loads notification pages lazily', () => {
    routes.forEach(route => {
      expect(typeof route.component).toBe('function');
      route.children.forEach(child => {
        expect(typeof child.component).toBe('function');
      });
    });
  });
});
