import store from './index';

const asyncStoreModuleLoaders = {
  agentBots: () => import('./modules/agentBots'),
  agentCapacityPolicies: () => import('./modules/agentCapacityPolicies'),
  assignmentPolicies: () => import('./modules/assignmentPolicies'),
  auditlogs: () => import('./modules/auditlogs'),
  automations: () => import('./modules/automations'),
  customRole: () => import('./modules/customRole'),
  csat: () => import('./modules/csat'),
  reports: () => import('./modules/reports'),
  slaReports: () => import('./modules/SLAReports'),
  summaryReports: () => import('./modules/summaryReports'),
  webhooks: () => import('./modules/webhooks'),
};

export const getAsyncStoreModulesForRoute = route => {
  return [...new Set(route.matched.flatMap(match => match.meta?.asyncStoreModules || []))];
};

export const buildAsyncStoreModuleLoader = ({
  moduleLoaders = asyncStoreModuleLoaders,
  store: targetStore = store,
} = {}) => {
  return async moduleNames => {
    const uniqueModuleNames = [...new Set(moduleNames)];

    await Promise.all(
      uniqueModuleNames.map(async moduleName => {
        if (targetStore.hasModule(moduleName)) {
          return;
        }

        const loadModule = moduleLoaders[moduleName];

        if (!loadModule) {
          throw new Error(`Unknown async store module: ${moduleName}`);
        }

        const moduleDefinition = await loadModule();
        targetStore.registerModule(moduleName, moduleDefinition.default);
      })
    );
  };
};

export const ensureStoreModules = buildAsyncStoreModuleLoader();
