import { vi } from 'vitest';

function mockComponent(name) {
  return { default: { name } };
}

vi.mock('../SettingsWrapper.vue', () => mockComponent('SettingsWrapper'));
vi.mock('./IntegrationHooks.vue', () => mockComponent('IntegrationHooks'));
vi.mock('./Index.vue', () => mockComponent('Index'));
vi.mock('./Webhooks/Index.vue', () => mockComponent('Webhook'));
vi.mock('./DashboardApps/Index.vue', () => mockComponent('DashboardApps'));
vi.mock('./Slack.vue', () => mockComponent('Slack'));
vi.mock('../Wrapper.vue', () => mockComponent('SettingsContent'));
vi.mock('./Linear.vue', () => mockComponent('Linear'));
vi.mock('./Notion.vue', () => mockComponent('Notion'));
vi.mock('./Shopify.vue', () => mockComponent('Shopify'));

import integrations from './integrations.routes';

const expectLazyComponents = routes => {
  routes.forEach(route => {
    if (route.component) {
      expect(typeof route.component).toBe('function');
    }

    if (route.children) {
      expectLazyComponents(route.children);
    }
  });
};

describe('settings integration routes', () => {
  it('loads integration pages lazily', () => {
    expectLazyComponents(integrations.routes);
  });
});
