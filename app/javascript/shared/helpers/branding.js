export const DEFAULT_BRAND_NAME = 'TA AI TECH';
const DEFAULT_BRAND_ORIGIN = 'https://taaitech.local';

const getWindow = () => (typeof window !== 'undefined' ? window : undefined);

const getGlobalConfig = () => getWindow()?.globalConfig || {};

const getRuntimeConfig = () => getWindow()?.chatwootConfig || {};

const parseUrl = value => {
  try {
    return new URL(value);
  } catch {
    return null;
  }
};

export const getBrandName = () => {
  const globalConfig = getGlobalConfig();

  return (
    globalConfig.installationName ||
    globalConfig.INSTALLATION_NAME ||
    globalConfig.brandName ||
    globalConfig.BRAND_NAME ||
    DEFAULT_BRAND_NAME
  );
};

export const getBrandUrl = () => {
  const globalConfig = getGlobalConfig();
  const runtimeConfig = getRuntimeConfig();

  return (
    globalConfig.brandURL ||
    globalConfig.BRAND_URL ||
    globalConfig.widgetBrandURL ||
    globalConfig.WIDGET_BRAND_URL ||
    runtimeConfig.helpCenterURL ||
    runtimeConfig.hostURL ||
    getWindow()?.location?.origin ||
    DEFAULT_BRAND_ORIGIN
  );
};

export const getBrandOrigin = () => {
  return (
    parseUrl(getBrandUrl())?.origin ||
    getWindow()?.location?.origin ||
    DEFAULT_BRAND_ORIGIN
  );
};

export const getBrandHost = () => {
  return parseUrl(getBrandOrigin())?.host || 'taaitech.local';
};

export const getTermsUrl = () => {
  const globalConfig = getGlobalConfig();

  return globalConfig.termsURL || globalConfig.TERMS_URL || getBrandUrl();
};

export const getPrivacyUrl = () => {
  const globalConfig = getGlobalConfig();

  return globalConfig.privacyURL || globalConfig.PRIVACY_URL || getBrandUrl();
};

export const replaceBrandingText = (text, brandName = getBrandName()) => {
  if (typeof text !== 'string' || !text) {
    return text;
  }

  return text
    .replace(
      /https?:\/\/www\.chatwoot\.com\/terms(?:-of-service)?/g,
      getTermsUrl()
    )
    .replace(
      /https?:\/\/www\.chatwoot\.com\/privacy-policy/g,
      getPrivacyUrl()
    )
    .replace(/https?:\/\/(?:app\.|www\.)?chatwoot\.com/g, getBrandOrigin())
    .replace(/\bapp\.chatwoot\.com\b/g, getBrandHost())
    .replace(/\bchatwoot\.com\b/g, getBrandHost())
    .replace(/\bchatwoot\.dev\b/g, getBrandHost())
    .replace(/\bchatwoot\b/g, brandName)
    .replace(/\bChatwoot\b/g, brandName);
};
