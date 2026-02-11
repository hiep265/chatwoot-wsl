import { frontendURL } from '../../../helper/URLHelper';

import AiControlPanel from './pages/AiControlPanel.vue';

const meta = {
  permissions: ['administrator', 'agent', 'custom_role'],
};

const PlaceholderRoute = {
  render: () => null,
};

export const routes = [
  {
    path: frontendURL('accounts/:accountId/ai-control'),
    redirect: to => ({
      name: 'ai_control_panel',
      params: to.params,
    }),
    meta,
  },
  {
    path: frontendURL('accounts/:accountId/ai-control/conversations'),
    alias: frontendURL('accounts/:accountId/ai-control/simple'),
    name: 'ai_control_panel',
    component: AiControlPanel,
    meta,
  },
  {
    path: frontendURL(
      'accounts/:accountId/ai-control/conversations/:conversation_id'
    ),
    alias: frontendURL('accounts/:accountId/ai-control/simple/:conversation_id'),
    name: 'ai_control_panel_conversation',
    component: AiControlPanel,
    meta,
  },
];

export const standaloneRoutes = [
  {
    path: frontendURL('accounts/:accountId/simple'),
    name: 'ai_control_simple',
    component: AiControlPanel,
    props: { standalone: true },
    meta,
  },
  {
    path: frontendURL('accounts/:accountId/simple/:conversation_id'),
    name: 'ai_control_simple_conversation',
    component: AiControlPanel,
    props: { standalone: true },
    meta,
  },
];

export const entryRoutes = [
  {
    path: '/simple',
    name: 'ai_control_simple_entry',
    component: PlaceholderRoute,
    meta,
  },
  {
    path: '/simple/:conversation_id',
    name: 'ai_control_simple_conversation_entry',
    component: PlaceholderRoute,
    meta,
  },
  {
    path: frontendURL('simple'),
    name: 'ai_control_app_simple_entry',
    component: PlaceholderRoute,
    meta,
  },
  {
    path: frontendURL('simple/:conversation_id'),
    name: 'ai_control_app_simple_conversation_entry',
    component: PlaceholderRoute,
    meta,
  },
];
