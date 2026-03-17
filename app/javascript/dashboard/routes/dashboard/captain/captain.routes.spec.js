import { vi } from 'vitest';

function mockComponent(name) {
  return { default: { name } };
}

vi.mock('./pages/CaptainPageRouteView.vue', () =>
  mockComponent('CaptainPageRouteView')
);
vi.mock('./pages/AssistantsIndexPage.vue', () =>
  mockComponent('AssistantsIndexPage')
);
vi.mock('./assistants/Index.vue', () =>
  mockComponent('AssistantEmptyStateIndex')
);
vi.mock('./assistants/settings/Settings.vue', () =>
  mockComponent('AssistantSettingsIndex')
);
vi.mock('./assistants/inboxes/Index.vue', () =>
  mockComponent('AssistantInboxesIndex')
);
vi.mock('./assistants/playground/Index.vue', () =>
  mockComponent('AssistantPlaygroundIndex')
);
vi.mock('./assistants/guardrails/Index.vue', () =>
  mockComponent('AssistantGuardrailsIndex')
);
vi.mock('./assistants/guidelines/Index.vue', () =>
  mockComponent('AssistantGuidelinesIndex')
);
vi.mock('./assistants/scenarios/Index.vue', () =>
  mockComponent('AssistantScenariosIndex')
);
vi.mock('./documents/Index.vue', () => mockComponent('DocumentsIndex'));
vi.mock('./responses/Index.vue', () => mockComponent('ResponsesIndex'));
vi.mock('./responses/Pending.vue', () =>
  mockComponent('ResponsesPendingIndex')
);
vi.mock('./tools/Index.vue', () => mockComponent('CustomToolsIndex'));

import { routes } from './captain.routes';

describe('captain routes', () => {
  it('loads captain pages lazily', () => {
    const [captainRoute] = routes;

    expect(typeof captainRoute.component).toBe('function');

    captainRoute.children.forEach(route => {
      expect(typeof route.component).toBe('function');
    });
  });
});
