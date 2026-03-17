import { describe, expect, it, vi } from 'vitest';

import {
  buildAsyncStoreModuleLoader,
  getAsyncStoreModulesForRoute,
} from './asyncModules';

describe('async store modules', () => {
  it('deduplicates async store modules collected from matched routes', () => {
    const route = {
      matched: [
        { meta: { asyncStoreModules: ['reports', 'csat'] } },
        { meta: { asyncStoreModules: ['reports', 'slaReports'] } },
        { meta: {} },
      ],
    };

    expect(getAsyncStoreModulesForRoute(route)).toEqual([
      'reports',
      'csat',
      'slaReports',
    ]);
  });

  it('registers only modules that are not already present in the store', async () => {
    const registerModule = vi.fn();
    const store = {
      hasModule: vi.fn(name => name === 'reports'),
      registerModule,
    };

    const moduleLoaders = {
      reports: vi.fn(),
      csat: vi.fn().mockResolvedValue({ default: { namespaced: true } }),
      slaReports: vi.fn().mockResolvedValue({ default: { namespaced: true } }),
    };

    const ensureStoreModules = buildAsyncStoreModuleLoader({
      moduleLoaders,
      store,
    });

    await ensureStoreModules(['reports', 'csat', 'slaReports', 'csat']);

    expect(moduleLoaders.reports).not.toHaveBeenCalled();
    expect(moduleLoaders.csat).toHaveBeenCalledTimes(1);
    expect(moduleLoaders.slaReports).toHaveBeenCalledTimes(1);
    expect(registerModule).toHaveBeenCalledTimes(2);
    expect(registerModule).toHaveBeenNthCalledWith(
      1,
      'csat',
      expect.objectContaining({ namespaced: true })
    );
    expect(registerModule).toHaveBeenNthCalledWith(
      2,
      'slaReports',
      expect.objectContaining({ namespaced: true })
    );
  });
});
