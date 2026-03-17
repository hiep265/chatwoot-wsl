import { describe, expect, it, vi, beforeEach, afterEach } from 'vitest';

import { resizeObserver } from './resizeObserver';

describe('resizeObserver directive', () => {
  let ResizeObserverMock;

  beforeEach(() => {
    ResizeObserverMock = vi.fn(callback => {
      return {
        callback,
        disconnect: vi.fn(),
        observe: vi.fn(),
      };
    });

    vi.stubGlobal('ResizeObserver', ResizeObserverMock);
  });

  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it('observes the bound element and forwards resize events to the handler', () => {
    const element = document.createElement('div');
    const handler = vi.fn();

    resizeObserver.mounted(element, { value: handler });

    const observer = ResizeObserverMock.mock.results[0].value;

    expect(observer.observe).toHaveBeenCalledWith(element);

    const entries = [{ target: element }];
    observer.callback(entries);

    expect(handler).toHaveBeenCalledWith(entries, observer);
  });

  it('disconnects the observer when the element is unmounted', () => {
    const element = document.createElement('div');
    const handler = vi.fn();

    resizeObserver.mounted(element, { value: handler });

    const observer = ResizeObserverMock.mock.results[0].value;

    resizeObserver.unmounted(element);

    expect(observer.disconnect).toHaveBeenCalledTimes(1);
  });
});
