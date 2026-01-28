import { frontendURL } from '../../../helper/URLHelper';

import AiControlPanel from './pages/AiControlPanel.vue';

const meta = {
  permissions: ['administrator', 'agent', 'custom_role'],
};

export const routes = [
  {
    path: frontendURL('accounts/:accountId/ai-control'),
    name: 'ai_control_panel',
    component: AiControlPanel,
    meta,
  },
];
