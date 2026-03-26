import { createRouter, createWebHistory } from 'vue-router';

import { frontendURL } from '../helper/URLHelper';
import dashboard from './dashboard/dashboard.routes';
import store from 'dashboard/store';
import {
  ensureStoreModules,
  getAsyncStoreModulesForRoute,
} from 'dashboard/store/asyncModules';
import { validateLoggedInRoutes } from '../helper/routeHelpers';
import AnalyticsHelper from '../helper/AnalyticsHelper';

const routes = [...dashboard.routes];

export const router = createRouter({ history: createWebHistory(), routes });

const AI_CONTROL_SIMPLE_ENTRY_ROUTES = new Set([
  'ai_control_simple_entry',
  'ai_control_simple_conversation_entry',
  'ai_control_app_simple_entry',
  'ai_control_app_simple_conversation_entry',
]);

const defaultTrackPage = (...args) => AnalyticsHelper.page(...args);

export const validateAuthenticateRoutePermission = (to, next) => {
  const { isLoggedIn, getCurrentUser: user } = store.getters;

  if (!isLoggedIn) {
    window.location.assign('/app/login');
    return '';
  }

  const { accounts = [], account_id: accountId } = user;

  if (!accounts.length) {
    if (to.name === 'no_accounts') {
      return next();
    }
    return next(frontendURL('no-accounts'));
  }

  if (to.name === 'no_accounts' || !to.name) {
    return next(frontendURL(`accounts/${accountId}/dashboard`));
  }

  if (AI_CONTROL_SIMPLE_ENTRY_ROUTES.has(String(to.name || ''))) {
    const conversationId = String(to.params.conversation_id || '').trim();
    const suffix = conversationId ? `simple/${conversationId}` : 'simple';
    return next(frontendURL(`accounts/${accountId}/${suffix}`));
  }

  const nextRoute = validateLoggedInRoutes(to, store.getters.getCurrentUser);
  return nextRoute ? next(frontendURL(nextRoute)) : next();
};

export const ensureAsyncStoreModulesForRoute = async to => {
  const asyncStoreModules = getAsyncStoreModulesForRoute(to);

  if (!asyncStoreModules.length) {
    return [];
  }

  /* eslint-disable no-console */
  console.log('[TaiStoreRoute] Bắt đầu luồng');
  console.log(
    '[TaiStoreRoute] Bước 1: Xác định module store cần tải',
    asyncStoreModules
  );

  try {
    await ensureStoreModules(asyncStoreModules);
    console.log('[TaiStoreRoute] Bước 2: Đã tải xong module store cho route');
    console.log('[TaiStoreRoute] Kết thúc luồng');
    return asyncStoreModules;
  } catch (error) {
    console.error(
      '[TaiStoreRoute] Lỗi tại bước 2: Không tải được module store cho route',
      error
    );
    throw error;
  } finally {
    /* eslint-enable no-console */
  }
};

export const trackPageViewForRoute = ({
  to,
  trackPage = defaultTrackPage,
} = {}) => {
  /* eslint-disable no-console */
  console.log('[DieuHuongRoute] Bắt đầu luồng');
  console.log('[DieuHuongRoute] Bước 1: Gửi sự kiện page view', {
    path: to?.path,
    name: to?.name,
  });

  try {
    trackPage(to?.name || '', {
      path: to?.path,
      name: to?.name,
    });
  } catch (error) {
    console.warn(
      '[DieuHuongRoute] Cảnh báo tại bước 1: Bỏ qua lỗi analytics khi chuyển trang',
      error
    );
  } finally {
    console.log('[DieuHuongRoute] Kết thúc luồng');
    /* eslint-enable no-console */
  }
};

export const handleBeforeEachNavigation = async ({
  to,
  next,
  userAuthentication,
  trackPage = defaultTrackPage,
  ensureRouteModules = ensureAsyncStoreModulesForRoute,
  validateRoutePermission = validateAuthenticateRoutePermission,
} = {}) => {
  trackPageViewForRoute({ to, trackPage });

  try {
    await userAuthentication;
    await ensureRouteModules(to);
    return validateRoutePermission(to, next, store);
  } catch (error) {
    return next(false);
  }
};

export const initalizeRouter = () => {
  const userAuthentication = store.dispatch('setUser');

  router.beforeEach((to, _from, next) => {
    return handleBeforeEachNavigation({
      to,
      next,
      userAuthentication,
    });
  });
};

export default router;
