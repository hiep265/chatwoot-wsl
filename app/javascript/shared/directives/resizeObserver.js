const resizeObserverMap = new WeakMap();

const cleanupObserver = element => {
  const observer = resizeObserverMap.get(element);
  if (!observer) {
    return;
  }

  observer.disconnect();
  resizeObserverMap.delete(element);
};

const createResizeObserver = (element, handler) => {
  if (typeof ResizeObserver === 'undefined' || typeof handler !== 'function') {
    return;
  }

  const observer = new ResizeObserver(entries => {
    handler(entries, observer);
  });

  observer.observe(element);
  resizeObserverMap.set(element, observer);
};

export const resizeObserver = {
  mounted(element, binding) {
    createResizeObserver(element, binding.value);
  },
  updated(element, binding) {
    if (binding.value === binding.oldValue) {
      return;
    }

    cleanupObserver(element);
    createResizeObserver(element, binding.value);
  },
  unmounted(element) {
    cleanupObserver(element);
  },
};
