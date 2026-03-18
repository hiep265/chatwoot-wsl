/* global globalThis */

const runWithTimeout = callback => {
  return globalThis.setTimeout(callback, 0);
};

export const scheduleAfterFirstPaint = callback => {
  let isCancelled = false;
  let animationFrameId = null;
  let idleCallbackId = null;
  let timeoutId = null;

  const runCallback = () => {
    if (!isCancelled) {
      callback();
    }
  };

  const scheduleIdleWork = () => {
    if (typeof globalThis.requestIdleCallback === 'function') {
      idleCallbackId = globalThis.requestIdleCallback(runCallback, {
        timeout: 1500,
      });
      return;
    }

    timeoutId = runWithTimeout(runCallback);
  };

  if (typeof globalThis.requestAnimationFrame === 'function') {
    animationFrameId = globalThis.requestAnimationFrame(scheduleIdleWork);
  } else {
    timeoutId = runWithTimeout(scheduleIdleWork);
  }

  return () => {
    isCancelled = true;

    if (
      animationFrameId !== null &&
      typeof globalThis.cancelAnimationFrame === 'function'
    ) {
      globalThis.cancelAnimationFrame(animationFrameId);
    }

    if (
      idleCallbackId !== null &&
      typeof globalThis.cancelIdleCallback === 'function'
    ) {
      globalThis.cancelIdleCallback(idleCallbackId);
    }

    if (timeoutId !== null) {
      globalThis.clearTimeout(timeoutId);
    }
  };
};

export const getConversationDisplayPreferencePatch = ({
  isSmallScreen,
  currentDisplayType,
  expandedLayoutType,
  previousDisplayType,
}) => {
  if (isSmallScreen) {
    if (currentDisplayType === expandedLayoutType) {
      return null;
    }

    return {
      conversation_display_type: expandedLayoutType,
    };
  }

  if (!previousDisplayType || previousDisplayType === currentDisplayType) {
    return null;
  }

  return {
    conversation_display_type: previousDisplayType,
  };
};
