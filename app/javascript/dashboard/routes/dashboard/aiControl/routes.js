import { frontendURL } from '../../../helper/URLHelper';

import AiControlPanel from './pages/AiControlPanel.vue';

const meta = {
  permissions: ['administrator', 'agent', 'custom_role'],
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
