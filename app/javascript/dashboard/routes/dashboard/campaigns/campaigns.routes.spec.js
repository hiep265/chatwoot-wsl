import { vi } from 'vitest';

function mockComponent(name) {
  return { default: { name } };
}

vi.mock('./pages/CampaignsPageRouteView.vue', () =>
  mockComponent('CampaignsPageRouteView')
);
vi.mock('./pages/LiveChatCampaignsPage.vue', () =>
  mockComponent('LiveChatCampaignsPage')
);
vi.mock('./pages/SMSCampaignsPage.vue', () =>
  mockComponent('SMSCampaignsPage')
);
vi.mock('./pages/WhatsAppCampaignsPage.vue', () =>
  mockComponent('WhatsAppCampaignsPage')
);

import campaigns from './campaigns.routes';

describe('campaign routes', () => {
  it('loads campaign pages lazily', () => {
    const [campaignsRoute] = campaigns.routes;

    expect(typeof campaignsRoute.component).toBe('function');

    campaignsRoute.children
      .filter(route => !route.redirect)
      .forEach(route => {
        expect(typeof route.component).toBe('function');
      });
  });
});
