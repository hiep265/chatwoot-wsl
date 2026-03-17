const DENY_URLS = [
  /^chrome:\/\//i,
  /chrome-extension:/i,
  /extensions\//i,
  /file:\/\//i,
  /safari-web-extension:/i,
  /safari-extension:/i,
];

const IGNORE_ERRORS = [
  'ResizeObserver loop completed with undelivered notifications',
];

let sentryModulePromise = null;
let sentryInitPromise = null;

const getSentryDsn = () => window?.errorLoggingConfig;

const loadSentry = async () => {
  if (!getSentryDsn()) {
    return null;
  }

  if (!sentryModulePromise) {
    sentryModulePromise = import('@sentry/vue').catch(error => {
      sentryModulePromise = null;
      throw error;
    });
  }

  return sentryModulePromise;
};

const withSentry = async callback => {
  try {
    const Sentry = await loadSentry();

    if (!Sentry) {
      return false;
    }

    await callback(Sentry);
    return true;
  } catch (error) {
    // eslint-disable-next-line no-console
    console.warn('Failed to load Sentry', error);
    return false;
  }
};

export const initializeSentry = async ({ app, router } = {}) => {
  const dsn = getSentryDsn();

  if (!dsn) {
    return false;
  }

  if (!sentryInitPromise) {
    sentryInitPromise = withSentry(Sentry => {
      Sentry.init({
        app,
        dsn,
        denyUrls: DENY_URLS,
        integrations: router
          ? [Sentry.browserTracingIntegration({ router })]
          : [],
        ignoreErrors: IGNORE_ERRORS,
      });
    }).then(result => {
      if (!result) {
        sentryInitPromise = null;
      }

      return result;
    });
  }

  return sentryInitPromise;
};

export const setSentryContext = async (name, context) =>
  withSentry(Sentry => {
    Sentry.setContext(name, context);
  });

export const captureException = async error =>
  withSentry(Sentry => {
    Sentry.captureException(error);
  });

export const captureExceptionWithContext = async (name, context, error) =>
  withSentry(Sentry => {
    if (name && context) {
      Sentry.setContext(name, context);
    }

    Sentry.captureException(error);
  });
