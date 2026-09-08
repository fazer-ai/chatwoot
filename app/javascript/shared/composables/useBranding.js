/**
 * Composable for branding-related utilities
 * Provides methods to customize text with installation-specific branding
 */
import { useMapGetter } from 'dashboard/composables/store.js';

export function useBranding() {
  const globalConfig = useMapGetter('globalConfig/get');
  /**
   * Replaces "Chatwoot" (any casing) in text with a brand name.
   *
   * The replace is what covers all 40-odd locales: only a handful of the strings are
   * translated in this fork, and interpolating a name into them would leave the rest saying
   * "Chatwoot" literally.
   *
   * @param {string} text - The text to process
   * @param {string} [brandName] - Name to use instead of the installation's. Pages served on
   *   behalf of one account pass the brand of that account; everything else omits it and
   *   keeps the installation name.
   * @returns {string} - Text with "Chatwoot" replaced
   */
  const replaceInstallationName = (text, brandName) => {
    if (!text) return text;

    const name = brandName || globalConfig.value?.installationName;
    if (!name) return text;

    return text.replace(/chatwoot/gi, name);
  };

  return {
    replaceInstallationName,
  };
}
