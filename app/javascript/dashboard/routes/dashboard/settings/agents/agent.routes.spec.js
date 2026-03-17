import { vi } from 'vitest';

function mockComponent(name) {
  return { default: { name } };
}

vi.mock('../SettingsWrapper.vue', () => mockComponent('SettingsWrapper'));
vi.mock('./Index.vue', () => mockComponent('AgentHome'));

import agent from './agent.routes';

describe('agent routes', () => {
  it('loads agent pages lazily', () => {
    agent.routes.forEach(route => {
      expect(typeof route.component).toBe('function');
      route.children
        .filter(child => !child.redirect)
        .forEach(child => {
          expect(typeof child.component).toBe('function');
        });
    });
  });
});
