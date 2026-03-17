// NOTE: In the future if performance becomes an issue, we can memoize the functions

import { unref } from 'vue';
import camelcaseKeys from 'camelcase-keys';
import snakecaseKeys from 'snakecase-keys';
import { captureExceptionWithContext } from 'shared/helpers/sentry';

/**
 * Vue composable that converts object keys to camelCase
 * @param {Object|Array|import('vue').Ref<Object|Array>} payload - Object or array to convert
 * @param {Object} [options] - Options object
 * @param {boolean} [options.deep=false] - Should convert keys of nested objects
 * @returns {Object|Array} Converted payload with camelCase keys
 */
export function useCamelCase(payload, options) {
  try {
    const unrefPayload = unref(payload);
    return camelcaseKeys(unrefPayload, options);
  } catch (e) {
    void captureExceptionWithContext(
      'transform-keys-error',
      {
        payload,
        options,
        op: 'camelCase',
      },
      e
    );
    return payload;
  }
}

/**
 * Vue composable that converts object keys to snake_case
 * @param {Object|Array|import('vue').Ref<Object|Array>} payload - Object or array to convert
 * @param {Object} [options] - Options object
 * @param {boolean} [options.deep=false] - Should convert keys of nested objects
 * @returns {Object|Array} Converted payload with snake_case keys
 */
export function useSnakeCase(payload, options) {
  try {
    const unrefPayload = unref(payload);
    return snakecaseKeys(unrefPayload, options);
  } catch (e) {
    void captureExceptionWithContext(
      'transform-keys-error',
      {
        payload,
        options,
        op: 'snakeCase',
      },
      e
    );
    return payload;
  }
}
