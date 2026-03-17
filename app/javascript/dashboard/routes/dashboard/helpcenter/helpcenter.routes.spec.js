import { vi } from 'vitest';

function mockComponent(name) {
  return { default: { name } };
}

vi.mock('./pages/HelpCenterPageRouteView.vue', () =>
  mockComponent('HelpCenterPageRouteView')
);
vi.mock('./pages/PortalsIndexPage.vue', () => mockComponent('PortalsIndex'));
vi.mock('./pages/PortalsNewPage.vue', () => mockComponent('PortalsNew'));

import helpcenterRoutes from './helpcenter.routes';

describe('helpcenter routes', () => {
  it('loads helpcenter pages lazily', () => {
    const [helpcenterRoute] = helpcenterRoutes.routes;

    expect(typeof helpcenterRoute.component).toBe('function');

    helpcenterRoute.children.forEach(route => {
      expect(typeof route.component).toBe('function');
    });
  });
});
