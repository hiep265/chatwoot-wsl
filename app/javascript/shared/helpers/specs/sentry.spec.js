const sentryMock = vi.hoisted(() => ({
  init: vi.fn(),
  browserTracingIntegration: vi.fn(() => 'browser-tracing'),
  setContext: vi.fn(),
  captureException: vi.fn(),
}));

vi.mock('@sentry/vue', () => ({
  init: sentryMock.init,
  browserTracingIntegration: sentryMock.browserTracingIntegration,
  setContext: sentryMock.setContext,
  captureException: sentryMock.captureException,
}));

const loadHelper = () => import('shared/helpers/sentry');

describe('shared/helpers/sentry', () => {
  beforeEach(() => {
    vi.resetModules();
    vi.clearAllMocks();
    delete window.errorLoggingConfig;
  });

  it('skips initialization when error logging is disabled', async () => {
    const { initializeSentry } = await loadHelper();

    await expect(initializeSentry({ app: {}, router: {} })).resolves.toBe(
      false
    );

    expect(sentryMock.init).not.toHaveBeenCalled();
    expect(sentryMock.browserTracingIntegration).not.toHaveBeenCalled();
  });

  it('initializes sentry with browser tracing when config is present', async () => {
    window.errorLoggingConfig = 'https://dsn.example/123';
    const app = { name: 'dashboard-app' };
    const router = { name: 'dashboard-router' };
    const { initializeSentry } = await loadHelper();

    await expect(initializeSentry({ app, router })).resolves.toBe(true);

    expect(sentryMock.browserTracingIntegration).toHaveBeenCalledWith({
      router,
    });
    expect(sentryMock.init).toHaveBeenCalledWith(
      expect.objectContaining({
        app,
        dsn: window.errorLoggingConfig,
        integrations: ['browser-tracing'],
      })
    );
  });

  it('sets context before capturing an exception', async () => {
    window.errorLoggingConfig = 'https://dsn.example/123';
    const error = new Error('boom');
    const { captureExceptionWithContext } = await loadHelper();

    await expect(
      captureExceptionWithContext(
        'transform-keys-error',
        { op: 'camelCase' },
        error
      )
    ).resolves.toBe(true);

    expect(sentryMock.setContext).toHaveBeenCalledWith(
      'transform-keys-error',
      { op: 'camelCase' }
    );
    expect(sentryMock.captureException).toHaveBeenCalledWith(error);
  });
});
