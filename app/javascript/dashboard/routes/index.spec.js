import { vi } from 'vitest';

vi.mock('vue-router', () => ({
  createRouter: vi.fn(() => ({
    beforeEach: vi.fn(),
  })),
  createWebHistory: vi.fn(() => ({})),
}));

vi.mock('./dashboard/dashboard.routes', () => ({
  default: {
    routes: [],
  },
}));

vi.mock('dashboard/store', () => ({
  default: {
    dispatch: vi.fn(),
    getters: {
      isLoggedIn: false,
      getCurrentUser: {
        account_id: null,
        id: null,
        accounts: [],
      },
    },
  },
}));

vi.mock('dashboard/store/asyncModules', () => ({
  ensureStoreModules: vi.fn(),
  getAsyncStoreModulesForRoute: vi.fn(),
}));

vi.mock('../helper/AnalyticsHelper', () => ({
  default: {
    analytics: {
      track: vi.fn(),
    },
    page: vi.fn(function page(pageName, properties = {}) {
      if (!this.analytics) {
        throw new TypeError(
          "Cannot read properties of undefined (reading 'analytics')"
        );
      }

      this.analytics.track('$pageview', {
        pageName,
        ...properties,
      });
    }),
  },
}));

import {
  ensureAsyncStoreModulesForRoute,
  handleBeforeEachNavigation,
  trackPageViewForRoute,
  validateAuthenticateRoutePermission,
} from './index';
import store from 'dashboard/store';
import {
  ensureStoreModules,
  getAsyncStoreModulesForRoute,
} from 'dashboard/store/asyncModules';
import AnalyticsHelper from '../helper/AnalyticsHelper';

describe('#validateAuthenticateRoutePermission', () => {
  let next;

  beforeEach(() => {
    next = vi.fn(); // Mock the next function
  });

  describe('when user is not logged in', () => {
    it('should redirect to login', () => {
      const to = { name: 'some-protected-route', params: { accountId: 1 } };

      // Mock the store to simulate user not logged in
      store.getters.isLoggedIn = false;

      // Mock window.location.assign
      const mockAssign = vi.fn();
      delete window.location;
      window.location = { assign: mockAssign };

      validateAuthenticateRoutePermission(to, next);

      expect(mockAssign).toHaveBeenCalledWith('/app/login');
    });
  });

  describe('when user is logged in', () => {
    beforeEach(() => {
      // Mock the store's getter for a logged-in user
      store.getters.isLoggedIn = true;
      store.getters.getCurrentUser = {
        account_id: 1,
        id: 1,
        accounts: [
          {
            id: 1,
            role: 'agent',
            permissions: ['agent'],
            status: 'active',
          },
        ],
      };
    });

    describe('when route is not accessible to current user', () => {
      it('should redirect to dashboard', () => {
        const to = {
          name: 'general_settings_index',
          params: { accountId: 1 },
          meta: { permissions: ['administrator'] },
        };

        validateAuthenticateRoutePermission(to, next);

        expect(next).toHaveBeenCalledWith('/app/accounts/1/dashboard');
      });
    });

    describe('when route is accessible to current user', () => {
      beforeEach(() => {
        // Adjust store getters to reflect the user has admin permissions
        store.getters.getCurrentUser = {
          account_id: 1,
          id: 1,
          accounts: [
            {
              id: 1,
              role: 'administrator',
              permissions: ['administrator'],
              status: 'active',
            },
          ],
        };
      });

      it('should go to the intended route', () => {
        const to = {
          name: 'general_settings_index',
          params: { accountId: 1 },
          meta: { permissions: ['administrator'] },
        };

        validateAuthenticateRoutePermission(to, next);

        expect(next).toHaveBeenCalledWith();
      });
    });
  });
});

describe('#ensureAsyncStoreModulesForRoute', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('runs_full_flow_when_route_declares_async_store_modules', async () => {
    const route = {
      matched: [{ meta: { asyncStoreModules: ['webhooks'] } }],
    };
    const logSpy = vi.spyOn(console, 'log').mockImplementation(() => {});
    const errorSpy = vi.spyOn(console, 'error').mockImplementation(() => {});

    getAsyncStoreModulesForRoute.mockReturnValue(['webhooks']);
    ensureStoreModules.mockResolvedValue();

    await expect(ensureAsyncStoreModulesForRoute(route)).resolves.toEqual([
      'webhooks',
    ]);

    expect(getAsyncStoreModulesForRoute).toHaveBeenCalledWith(route);
    expect(ensureStoreModules).toHaveBeenCalledWith(['webhooks']);
    expect(logSpy.mock.calls).toEqual([
      ['[TaiStoreRoute] Bắt đầu luồng'],
      ['[TaiStoreRoute] Bước 1: Xác định module store cần tải', ['webhooks']],
      ['[TaiStoreRoute] Bước 2: Đã tải xong module store cho route'],
      ['[TaiStoreRoute] Kết thúc luồng'],
    ]);
    expect(errorSpy).not.toHaveBeenCalled();
  });

  it('uses_existing_branch_when_route_has_no_async_store_modules', async () => {
    getAsyncStoreModulesForRoute.mockReturnValue([]);

    await expect(
      ensureAsyncStoreModulesForRoute({ matched: [] })
    ).resolves.toEqual([]);

    expect(ensureStoreModules).not.toHaveBeenCalled();
  });

  it('stops_flow_at_step_2_when_async_store_module_loading_fails', async () => {
    const route = {
      matched: [{ meta: { asyncStoreModules: ['webhooks'] } }],
    };
    const logSpy = vi.spyOn(console, 'log').mockImplementation(() => {});
    const errorSpy = vi.spyOn(console, 'error').mockImplementation(() => {});
    const loadError = new Error('load failed');

    getAsyncStoreModulesForRoute.mockReturnValue(['webhooks']);
    ensureStoreModules.mockRejectedValue(loadError);

    await expect(ensureAsyncStoreModulesForRoute(route)).rejects.toThrow(
      'load failed'
    );

    expect(logSpy.mock.calls).toEqual([
      ['[TaiStoreRoute] Bắt đầu luồng'],
      ['[TaiStoreRoute] Bước 1: Xác định module store cần tải', ['webhooks']],
    ]);
    expect(errorSpy).toHaveBeenCalledWith(
      '[TaiStoreRoute] Lỗi tại bước 2: Không tải được module store cho route',
      loadError
    );
  });
});

describe('#handleBeforeEachNavigation', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('loads_route_modules_before_validating_permissions', async () => {
    const next = vi.fn();
    const userAuthentication = Promise.resolve();
    const ensureRouteModules = vi.fn().mockResolvedValue([]);
    const validateRoutePermission = vi.fn();
    const route = { name: 'settings_integrations_webhook', path: '/app/test' };

    await handleBeforeEachNavigation({
      to: route,
      next,
      userAuthentication,
      ensureRouteModules,
      validateRoutePermission,
    });

    expect(AnalyticsHelper.page).toHaveBeenCalledWith(
      'settings_integrations_webhook',
      {
        path: '/app/test',
        name: 'settings_integrations_webhook',
      }
    );
    expect(ensureRouteModules).toHaveBeenCalledWith(route);
    expect(validateRoutePermission).toHaveBeenCalledWith(route, next, store);
    expect(ensureRouteModules.mock.invocationCallOrder[0]).toBeLessThan(
      validateRoutePermission.mock.invocationCallOrder[0]
    );
  });

  it('stops_flow_at_step_2_when_route_module_preparation_fails', async () => {
    const next = vi.fn();
    const userAuthentication = Promise.resolve();
    const ensureRouteModules = vi.fn().mockRejectedValue(new Error('boom'));
    const validateRoutePermission = vi.fn();

    await handleBeforeEachNavigation({
      to: { name: 'settings_integrations_webhook', path: '/app/test' },
      next,
      userAuthentication,
      ensureRouteModules,
      validateRoutePermission,
    });

    expect(validateRoutePermission).not.toHaveBeenCalled();
    expect(next).toHaveBeenCalledWith(false);
  });
});

describe('#trackPageViewForRoute', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('runs_full_flow_when_page_tracking_succeeds', () => {
    const logSpy = vi.spyOn(console, 'log').mockImplementation(() => {});
    const warnSpy = vi.spyOn(console, 'warn').mockImplementation(() => {});
    const route = { name: 'ai_control_simple_entry', path: '/app/test' };

    trackPageViewForRoute({ to: route });

    expect(AnalyticsHelper.page).toHaveBeenCalledWith(
      'ai_control_simple_entry',
      {
        path: '/app/test',
        name: 'ai_control_simple_entry',
      }
    );
    expect(AnalyticsHelper.analytics.track).toHaveBeenCalledWith('$pageview', {
      pageName: 'ai_control_simple_entry',
      path: '/app/test',
      name: 'ai_control_simple_entry',
    });
    expect(logSpy.mock.calls).toEqual([
      ['[DieuHuongRoute] Bắt đầu luồng'],
      [
        '[DieuHuongRoute] Bước 1: Gửi sự kiện page view',
        {
          path: '/app/test',
          name: 'ai_control_simple_entry',
        },
      ],
      ['[DieuHuongRoute] Kết thúc luồng'],
    ]);
    expect(warnSpy).not.toHaveBeenCalled();
  });

  it('uses_existing_branch_when_page_tracking_fails', () => {
    const warnSpy = vi.spyOn(console, 'warn').mockImplementation(() => {});
    const trackPage = vi.fn(() => {
      throw new Error('analytics failed');
    });

    expect(() =>
      trackPageViewForRoute({
        to: { name: 'ai_control_simple_entry', path: '/app/test' },
        trackPage,
      })
    ).not.toThrow();

    expect(warnSpy).toHaveBeenCalledWith(
      '[DieuHuongRoute] Cảnh báo tại bước 1: Bỏ qua lỗi analytics khi chuyển trang',
      expect.objectContaining({ message: 'analytics failed' })
    );
  });
});
