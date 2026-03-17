import { vi } from 'vitest';

function mockComponent(name) {
  return { default: { name } };
}

vi.mock('./Index.vue', () => mockComponent('TeamsIndex'));
vi.mock('./Create/Index.vue', () => mockComponent('CreateStepWrap'));
vi.mock('./Edit/Index.vue', () => mockComponent('EditStepWrap'));
vi.mock('./Create/CreateTeam.vue', () => mockComponent('CreateTeam'));
vi.mock('./Edit/EditTeam.vue', () => mockComponent('EditTeam'));
vi.mock('./Create/AddAgents.vue', () => mockComponent('AddAgents'));
vi.mock('./Edit/EditAgents.vue', () => mockComponent('EditAgents'));
vi.mock('./FinishSetup.vue', () => mockComponent('FinishSetup'));
vi.mock('../Wrapper.vue', () => mockComponent('SettingsContent'));
vi.mock('../SettingsWrapper.vue', () => mockComponent('SettingsWrapper'));

import teamsRoutes from './teams.routes';

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

describe('settings team routes', () => {
  it('loads team pages lazily', () => {
    expectLazyComponents(teamsRoutes.routes);
  });
});
