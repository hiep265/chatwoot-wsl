# Account Social App Config Design

## Goal

Allow each Chatwoot workspace (`Account`) to use its own social platform application credentials, managed by a super admin from that account's super admin page, while preserving the current installation-wide settings as a fallback.

## Background

Chatwoot stores most inbox credentials directly on channel records. For example, Telegram bot tokens, LINE channel credentials, WhatsApp Cloud manual API keys, Twilio credentials, Facebook page tokens, Instagram access tokens, and TikTok access tokens already belong to a specific inbox/channel.

Some application-level credentials are still installation-wide through `InstallationConfig`, `GlobalConfigService`, or environment variables:

- Facebook Messenger: `FB_APP_ID`, `FB_APP_SECRET`, `FB_VERIFY_TOKEN`, `FACEBOOK_API_VERSION`, `ENABLE_MESSENGER_CHANNEL_HUMAN_AGENT`
- Instagram direct login: `INSTAGRAM_APP_ID`, `INSTAGRAM_APP_SECRET`, `INSTAGRAM_VERIFY_TOKEN`, `INSTAGRAM_API_VERSION`, `ENABLE_INSTAGRAM_CHANNEL_HUMAN_AGENT`
- TikTok: `TIKTOK_APP_ID`, `TIKTOK_APP_SECRET`
- WhatsApp Embedded Signup: `WHATSAPP_APP_ID`, `WHATSAPP_APP_SECRET`, `WHATSAPP_CONFIGURATION_ID`, `WHATSAPP_API_VERSION`
- Twitter/X: `TWITTER_APP_ID`, `TWITTER_CONSUMER_KEY`, `TWITTER_CONSUMER_SECRET`, `TWITTER_ENVIRONMENT`

The requested behavior is account-level isolation for those application-level credentials.

## Scope

In scope:

- Add account-level social app configuration for Facebook, Instagram, TikTok, WhatsApp Embedded Signup, and Twitter/X.
- Add super admin UI on the account page so a super admin can view and edit these settings for a workspace.
- Update dashboard boot config so account pages load the app ids and API versions for the current account.
- Update OAuth token exchange, webhook verification, signature validation, and send helpers to resolve credentials from the account first.
- Keep global installation config as fallback for accounts without custom credentials.
- Add tests for model validation, resolver fallback, key OAuth/webhook flows, and super admin UI plumbing.

Out of scope:

- Moving inbox-level credentials that are already per-channel, such as Telegram bot token, LINE token/secret, Twilio credentials, WhatsApp manual Cloud API key, and page/channel access tokens.
- Building workspace-user-level overrides.
- Removing the existing global app config screens.

## Data Model

Create `account_social_app_configs`.

Columns:

- `id`
- `account_id`, required, foreign key to `accounts`
- `provider`, required string
- `app_id`, optional string
- `app_secret`, optional string
- `verify_token`, optional string
- `configuration_id`, optional string
- `api_version`, optional string
- `consumer_key`, optional string
- `consumer_secret`, optional string
- `environment`, optional string
- `settings`, jsonb, default `{}`
- timestamps

Indexes:

- unique index on `account_id, provider`
- index on `provider`

Providers:

- `facebook`
- `instagram`
- `tiktok`
- `whatsapp_embedded`
- `twitter`

Secrets:

- Encrypt `app_secret`, `verify_token`, and `consumer_secret` when `Chatwoot.encryption_configured?` is true.
- Keep deterministic encryption off unless a specific lookup requires it. Resolver lookups will use `account_id` and `provider`, not the encrypted secret value.

Associations:

- `Account has_many :social_app_configs, class_name: 'AccountSocialAppConfig'`
- `AccountSocialAppConfig belongs_to :account`

## Resolver

Add a resolver service responsible for mapping account-level values to current global config names.

Proposed API:

```ruby
AccountSocialAppConfigResolver.new(account).load('FB_APP_ID', '')
AccountSocialAppConfigResolver.new(account).load('TIKTOK_APP_SECRET', nil)
```

Resolution order:

1. If `account` is present and it has a matching provider config with the mapped field present, return that value.
2. Otherwise return `GlobalConfigService.load(config_key, default_value)`.

This keeps existing behavior for accounts that do not have custom config.

Mapping:

- `FB_APP_ID` -> `facebook.app_id`
- `FB_APP_SECRET` -> `facebook.app_secret`
- `FB_VERIFY_TOKEN` -> `facebook.verify_token`
- `FACEBOOK_API_VERSION` -> `facebook.api_version`
- `ENABLE_MESSENGER_CHANNEL_HUMAN_AGENT` -> `facebook.settings['enable_human_agent']`
- `INSTAGRAM_APP_ID` -> `instagram.app_id`
- `INSTAGRAM_APP_SECRET` -> `instagram.app_secret`
- `INSTAGRAM_VERIFY_TOKEN` -> `instagram.verify_token`
- `INSTAGRAM_API_VERSION` -> `instagram.api_version`
- `ENABLE_INSTAGRAM_CHANNEL_HUMAN_AGENT` -> `instagram.settings['enable_human_agent']`
- `TIKTOK_APP_ID` -> `tiktok.app_id`
- `TIKTOK_APP_SECRET` -> `tiktok.app_secret`
- `WHATSAPP_APP_ID` -> `whatsapp_embedded.app_id`
- `WHATSAPP_APP_SECRET` -> `whatsapp_embedded.app_secret`
- `WHATSAPP_CONFIGURATION_ID` -> `whatsapp_embedded.configuration_id`
- `WHATSAPP_API_VERSION` -> `whatsapp_embedded.api_version`
- `TWITTER_APP_ID` -> `twitter.app_id`
- `TWITTER_CONSUMER_KEY` -> `twitter.consumer_key`
- `TWITTER_CONSUMER_SECRET` -> `twitter.consumer_secret`
- `TWITTER_ENVIRONMENT` -> `twitter.environment`

## Super Admin UI

The super admin should edit workspace social credentials from the super admin account page.

Behavior:

- Add `social_app_configs` to the super admin account show page.
- Add a dedicated account-level edit section/page under the account route, for example:
  - `GET /super_admin/accounts/:account_id/social_app_configs/edit`
  - `PATCH /super_admin/accounts/:account_id/social_app_configs`
- The account show page links to this edit page.
- The edit page renders grouped forms for Facebook, Instagram, TikTok, WhatsApp Embedded Signup, and Twitter/X.
- Secret fields render as password fields with the same show/hide affordance currently used in `super_admin/app_configs`.
- Empty fields are allowed and mean "fallback to global installation config".
- Saving creates or updates one `AccountSocialAppConfig` per provider.
- Validation errors return to the same page and show the relevant error messages.

Why a dedicated nested page instead of editing inside `AccountDashboard::FORM_ATTRIBUTES`:

- Administrate nested json/secret editing is awkward in the generic account form.
- A dedicated page keeps normal account fields clean and makes the social app config intent explicit.
- It avoids accidental changes to unrelated account attributes.

## Backend Flow Changes

Dashboard boot config:

- `DashboardController` must resolve app ids and API versions using the current account when the request path includes `/app/accounts/:account_id`.
- For pages without account context, it should keep using global config.
- `window.chatwootConfig` should continue exposing the same frontend keys:
  - `fbAppId`
  - `instagramAppId`
  - `tiktokAppId`
  - `fbApiVersion`
  - `whatsappAppId`
  - `whatsappConfigurationId`
  - `whatsappApiVersion`

Facebook Messenger:

- Page registration and reauthorization must exchange long-lived tokens with the current account's `FB_APP_ID` and `FB_APP_SECRET`.
- Webhook verification must accept the account-level `FB_VERIFY_TOKEN` for the page receiving the webhook. Since Meta verification requests can arrive before a page is known, verification should accept any configured account-level Facebook verify token, plus the global fallback token.
- `app_secret_for(page_id)` should find the `Channel::FacebookPage` by `page_id`, use that page's account config, and fallback to global config.
- Instagram Messenger send through Facebook pages should compute `appsecret_proof` with the page account's Facebook app secret.
- Echo detection should compare against the page account's `FB_APP_ID` where page context is available. If no page context is available, fallback to global behavior.

Instagram direct login:

- Auth URL generation, callback token exchange, token verification, and long-lived-token exchange must use the account's Instagram config.
- The JWT `state` token must be verifiable after redirect. The implementation should encode the account id in a signed state using an installation secret or a resolver that can first decode account id safely, then verify with the account's Instagram app secret.
- Webhook verification should accept any configured account-level Instagram verify token, plus the global fallback `INSTAGRAM_VERIFY_TOKEN` and legacy `IG_VERIFY_TOKEN`.

TikTok:

- Auth URL generation and callback token exchange must use the account's TikTok config.
- Token refresh must use the channel account's TikTok config.
- Webhook signature verification should resolve the TikTok secret by identifying the account from the event payload if possible. If the provider payload does not include enough account identity before signature validation, the controller should verify against all configured account-level TikTok secrets plus the global fallback secret.

WhatsApp Embedded Signup:

- Frontend embedded signup config must use the current account's WhatsApp app id, configuration id, and API version.
- Code exchange and token debug must use the account's WhatsApp app id and app secret.
- Existing WhatsApp Cloud manual setup remains per-channel through `provider_config` and does not change.

Twitter/X:

- OAuth request token, callback token exchange, send service, direct message media fetch, and channel client must use the account's Twitter consumer key/secret/environment.
- CRC verification currently uses one global secret. For account-level apps, register account-specific webhook URLs, for example `/webhooks/twitter/:account_id`.
- CRC and event POST for `/webhooks/twitter/:account_id` use that account's Twitter config.
- Keep the existing `/webhooks/twitter` route as a global fallback for accounts using installation-wide config.

## Error Handling

- If an account-level config is incomplete for a provider, the resolver falls back field-by-field to global config.
- If both account-level and global config are missing for a required OAuth action, return the existing failure response and log which provider/config key was missing.
- Super admin save should not test external provider credentials; it only validates local shape and allowed providers.
- OAuth callback errors should keep redirecting to the existing channel creation error pages.

## Security

- Do not expose app secrets, verify tokens, or consumer secrets in dashboard boot config or normal account APIs.
- Only super admins can read or edit `AccountSocialAppConfig`.
- Secret values should not be included in logs.
- When rendering the super admin edit form, secret fields can show existing values in password inputs, matching the current super admin app config behavior.

## Testing

Backend tests:

- Model validation for allowed providers and uniqueness per account.
- Encryption guard specs where consistent with existing encrypted channel specs.
- Resolver specs for account override, field fallback, and global fallback.
- Dashboard controller spec proving account-scoped app ids are exposed for account routes.
- Facebook page callback spec proving long-lived token exchange uses account-level Facebook app credentials.
- Facebook webhook provider spec proving verify/app-secret lookup can use account-level config.
- Instagram concern/callback/helper specs for account-level app credentials and state handling.
- TikTok auth/token/webhook specs for account-level app credentials.
- WhatsApp Facebook API client specs for account-level app credentials.
- Twitter auth/webhook/send specs for account-level consumer credentials and account-specific webhook URL.
- Super admin controller specs for listing, saving, and authorization.

Frontend tests:

- Super admin view rendering grouped provider forms.
- Secret show/hide button behavior if implemented with custom JavaScript.
- Existing channel creation UI still reads the same `window.chatwootConfig` keys.

## Rollout

- Existing installations continue working because global config remains the fallback.
- No migration copies global settings into account configs.
- Super admins can gradually add account-level configs only for workspaces that need separate provider apps.
- The old global app config pages remain available as defaults.
