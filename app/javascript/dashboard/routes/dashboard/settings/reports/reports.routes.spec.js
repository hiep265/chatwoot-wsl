import { vi } from 'vitest';

function mockComponent(name) {
  return { default: { name } };
}

vi.mock('./components/ReportsWrapper.vue', () =>
  mockComponent('ReportsWrapper')
);
vi.mock('./Index.vue', () => mockComponent('Index'));
vi.mock('./AgentReportsIndex.vue', () =>
  mockComponent('AgentReportsIndex')
);
vi.mock('./InboxReportsIndex.vue', () =>
  mockComponent('InboxReportsIndex')
);
vi.mock('./TeamReportsIndex.vue', () => mockComponent('TeamReportsIndex'));
vi.mock('./LabelReportsIndex.vue', () => mockComponent('LabelReportsIndex'));
vi.mock('./AgentReportsShow.vue', () => mockComponent('AgentReportsShow'));
vi.mock('./InboxReportsShow.vue', () => mockComponent('InboxReportsShow'));
vi.mock('./TeamReportsShow.vue', () => mockComponent('TeamReportsShow'));
vi.mock('./LabelReportsShow.vue', () => mockComponent('LabelReportsShow'));
vi.mock('./AgentReports.vue', () => mockComponent('AgentReports'));
vi.mock('./InboxReports.vue', () => mockComponent('InboxReports'));
vi.mock('./LabelReports.vue', () => mockComponent('LabelReports'));
vi.mock('./TeamReports.vue', () => mockComponent('TeamReports'));
vi.mock('./CsatResponses.vue', () => mockComponent('CsatResponses'));
vi.mock('./BotReports.vue', () => mockComponent('BotReports'));
vi.mock('./LiveReports.vue', () => mockComponent('LiveReports'));
vi.mock('./SLAReports.vue', () => mockComponent('SLAReports'));

import reports from './reports.routes';

describe('reports routes', () => {
  it('loads report pages lazily', () => {
    const [reportsRoute] = reports.routes;

    expect(typeof reportsRoute.component).toBe('function');

    reportsRoute.children
      .filter(route => !route.redirect)
      .forEach(route => {
        expect(typeof route.component).toBe('function');
      });
  });
});
