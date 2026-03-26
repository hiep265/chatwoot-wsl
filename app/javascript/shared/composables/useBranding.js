/**
 * Composable for branding-related utilities
 * Provides methods to customize text with installation-specific branding
 */
import { useMapGetter } from 'dashboard/composables/store.js';
import { replaceBrandingText } from 'shared/helpers/branding';

export function useBranding() {
  const globalConfig = useMapGetter('globalConfig/get');
  /**
   * Replaces visible Chatwoot branding in text with the installation name
   * @param {string} text - The text to process
   * @returns {string} - Text with Chatwoot branding replaced by installation name
   */
  const replaceInstallationName = text => {
    if (!text) return text;

    const installationName = globalConfig.value?.installationName;
    if (!installationName) return text;

    return replaceBrandingText(text, installationName);
  };

  return {
    replaceInstallationName,
  };
}
