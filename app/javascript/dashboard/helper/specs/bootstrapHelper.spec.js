import {
  getConversationDisplayPreferencePatch,
  scheduleAfterFirstPaint,
} from 'dashboard/helper/bootstrapHelper';

describe('getConversationDisplayPreferencePatch', () => {
  it('returns an expanded layout update on small screens when needed', () => {
    expect(
      getConversationDisplayPreferencePatch({
        isSmallScreen: true,
        currentDisplayType: 'condensed',
        expandedLayoutType: 'expanded',
        previousDisplayType: 'condensed',
      })
    ).toEqual({
      conversation_display_type: 'expanded',
    });
  });

  it('returns null when the small screen layout already matches', () => {
    expect(
      getConversationDisplayPreferencePatch({
        isSmallScreen: true,
        currentDisplayType: 'expanded',
        expandedLayoutType: 'expanded',
        previousDisplayType: 'condensed',
      })
    ).toBeNull();
  });

  it('restores the previous layout on large screens when available', () => {
    expect(
      getConversationDisplayPreferencePatch({
        isSmallScreen: false,
        currentDisplayType: 'expanded',
        expandedLayoutType: 'expanded',
        previousDisplayType: 'condensed',
      })
    ).toEqual({
      conversation_display_type: 'condensed',
    });
  });

  it('returns null when there is no previous layout to restore', () => {
    expect(
      getConversationDisplayPreferencePatch({
        isSmallScreen: false,
        currentDisplayType: 'expanded',
        expandedLayoutType: 'expanded',
        previousDisplayType: undefined,
      })
    ).toBeNull();
  });
});

describe('scheduleAfterFirstPaint', () => {
  afterEach(() => {
    vi.useRealTimers();
    vi.unstubAllGlobals();
  });

  it('schedules work through requestIdleCallback when available', () => {
    const callback = vi.fn();
    const requestAnimationFrameSpy = vi.fn(cb => {
      cb();
      return 1;
    });
    const requestIdleCallbackSpy = vi.fn(cb => {
      cb();
      return 2;
    });

    vi.stubGlobal('requestAnimationFrame', requestAnimationFrameSpy);
    vi.stubGlobal('cancelAnimationFrame', vi.fn());
    vi.stubGlobal('requestIdleCallback', requestIdleCallbackSpy);
    vi.stubGlobal('cancelIdleCallback', vi.fn());

    scheduleAfterFirstPaint(callback);

    expect(requestAnimationFrameSpy).toHaveBeenCalledTimes(1);
    expect(requestIdleCallbackSpy).toHaveBeenCalledTimes(1);
    expect(callback).toHaveBeenCalledTimes(1);
  });

  it('falls back to setTimeout when requestIdleCallback is unavailable', () => {
    vi.useFakeTimers();

    const callback = vi.fn();
    vi.stubGlobal('requestAnimationFrame', cb => {
      cb();
      return 1;
    });
    vi.stubGlobal('cancelAnimationFrame', vi.fn());
    vi.stubGlobal('requestIdleCallback', undefined);

    scheduleAfterFirstPaint(callback);

    expect(callback).not.toHaveBeenCalled();

    vi.runAllTimers();

    expect(callback).toHaveBeenCalledTimes(1);
  });

  it('cancels pending work', () => {
    vi.useFakeTimers();

    const callback = vi.fn();
    let animationFrameCallback = null;

    vi.stubGlobal('requestAnimationFrame', cb => {
      animationFrameCallback = cb;
      return 1;
    });
    vi.stubGlobal('cancelAnimationFrame', vi.fn());
    vi.stubGlobal('requestIdleCallback', undefined);

    const cancel = scheduleAfterFirstPaint(callback);
    cancel();
    animationFrameCallback();
    vi.runAllTimers();

    expect(callback).not.toHaveBeenCalled();
  });
});
