import {
  getBrandName,
  getBrandUrl,
  replaceBrandingText,
} from '../branding';

describe('branding helper', () => {
  beforeEach(() => {
    window.globalConfig = {
      installationName: 'MyCompany',
      BRAND_URL: 'https://example.com',
      TERMS_URL: 'https://example.com/legal/terms',
      PRIVACY_URL: 'https://example.com/legal/privacy',
    };
    window.chatwootConfig = {
      hostURL: 'https://fallback.example.com',
    };
  });

  afterEach(() => {
    delete window.globalConfig;
    delete window.chatwootConfig;
  });

  it('returns the configured brand name', () => {
    expect(getBrandName()).toBe('MyCompany');
  });

  it('returns the configured brand url', () => {
    expect(getBrandUrl()).toBe('https://example.com');
  });

  it('replaces Chatwoot references with the configured brand values', () => {
    const text =
      'Welcome to Chatwoot. Docs: https://www.chatwoot.com/docs/product/ and app.chatwoot.com/hc/demo.';

    expect(replaceBrandingText(text)).toBe(
      'Welcome to MyCompany. Docs: https://example.com/docs/product/ and example.com/hc/demo.'
    );
  });

  it('replaces lowercase chatwoot references with the configured brand name', () => {
    expect(replaceBrandingText('chatwoot dashboard')).toBe(
      'MyCompany dashboard'
    );
  });

  it('replaces terms and privacy links with configured legal urls', () => {
    const text =
      'https://www.chatwoot.com/terms and https://www.chatwoot.com/privacy-policy';

    expect(replaceBrandingText(text)).toBe(
      'https://example.com/legal/terms and https://example.com/legal/privacy'
    );
  });
});
