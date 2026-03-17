import { vi } from 'vitest';

function mockComponent(name) {
  return { default: { name } };
}

vi.mock('../SettingsWrapper.vue', () => mockComponent('SettingsWrapper'));
vi.mock('./Index.vue', () => mockComponent('AssignmentPolicyIndex'));
vi.mock('./pages/AgentAssignmentIndexPage.vue', () =>
  mockComponent('AgentAssignmentIndex')
);
vi.mock('./pages/AgentAssignmentCreatePage.vue', () =>
  mockComponent('AgentAssignmentCreate')
);
vi.mock('./pages/AgentAssignmentEditPage.vue', () =>
  mockComponent('AgentAssignmentEdit')
);
vi.mock('./pages/AgentCapacityIndexPage.vue', () =>
  mockComponent('AgentCapacityIndex')
);
vi.mock('./pages/AgentCapacityCreatePage.vue', () =>
  mockComponent('AgentCapacityCreate')
);
vi.mock('./pages/AgentCapacityEditPage.vue', () =>
  mockComponent('AgentCapacityEdit')
);

import assignmentPolicy from './assignmentPolicy.routes';

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

describe('settings assignment policy routes', () => {
  it('loads assignment policy pages lazily', () => {
    expectLazyComponents(assignmentPolicy.routes);
  });
});
