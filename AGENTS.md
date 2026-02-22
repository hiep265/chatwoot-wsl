# Chatwoot Development Guidelines

## Project Overview

Chatwoot is a modern, open-source customer support platform - an alternative to Intercom, Zendesk, and Salesforce Service Cloud. It provides omnichannel support (live chat, email, social media, messaging apps), a help center portal, and AI-powered features through "Captain".

**Repository Structure:**
- **Monorepo**: Rails backend + Vue.js frontend in a single codebase
- **Dual Edition**: Open Source (OSS) with Enterprise Edition overlay in `enterprise/`
- **Base Branch**: `develop` (uses git-flow branching model)

## Technology Stack

### Backend (Ruby on Rails)
- **Ruby Version**: 3.4.4 (managed via rbenv)
- **Rails Version**: ~> 7.1
- **Database**: PostgreSQL 16+ with pgvector extension
- **Cache/Queue**: Redis with namespaces
- **Background Jobs**: Sidekiq with cron support (sidekiq-cron)
- **Search**: Searchkick with OpenSearch
- **Authentication**: Devise with token auth, JWT, OAuth2
- **Authorization**: Pundit
- **Storage**: Active Storage (local/S3/Azure/GCS)

### Frontend (Vue.js)
- **Framework**: Vue 3 with Composition API (`<script setup>`)
- **Build Tool**: Vite 5.x with vite-plugin-ruby
- **State Management**: Pinia (stores in `app/javascript/dashboard/stores/`)
- **Legacy State**: Vuex (being migrated)
- **Routing**: Vue Router 4.x
- **i18n**: Vue I18n 9.x
- **UI Framework**: Tailwind CSS 3.x only (no custom CSS)
- **Icons**: Iconify with custom collections

### Package Management
- **Ruby**: Bundler (`Gemfile`)
- **Node.js**: pnpm 10.x (required, enforced by `packageManager` field)
- **Node Version**: 24.x

## Project Architecture

### Directory Structure

```
/
├── app/
│   ├── controllers/          # Rails controllers
│   ├── models/               # ActiveRecord models
│   ├── services/             # Business logic services
│   ├── jobs/                 # ActiveJob/Sidekiq jobs
│   ├── policies/             # Pundit authorization
│   ├── views/                # ERB/Jbuilder templates
│   ├── javascript/           # Frontend source
│   │   ├── dashboard/        # Main dashboard app
│   │   │   ├── components/       # Legacy components
│   │   │   ├── components-next/  # New components (use this)
│   │   │   ├── routes/           # Vue routes
│   │   │   ├── stores/           # Pinia stores
│   │   │   ├── i18n/             # Translations (en.json)
│   │   │   └── api/              # API clients
│   │   ├── widget/           # Embeddable chat widget
│   │   ├── portal/           # Help center portal
│   │   ├── survey/           # CSAT surveys
│   │   ├── entrypoints/      # Vite entry points
│   │   └── shared/           # Shared utilities
│   └── channels/             # ActionCable channels
├── config/
│   ├── routes.rb             # All routes (extensive)
│   ├── app.yml               # App configuration
│   └── initializers/         # Rails initializers
├── db/
│   ├── migrate/              # Migrations
│   └── schema.rb             # Database schema
├── enterprise/               # Enterprise Edition overlay
│   ├── app/                  # EE controllers, models, services
│   ├── lib/                  # EE libraries
│   └── config/initializers/  # EE initializers
├── lib/                      # Shared libraries
│   ├── custom_exceptions/    # Custom error classes
│   ├── integrations/         # Third-party integrations
│   ├── seeders/              # Database seeders
│   └── tasks/                # Rake tasks
├── spec/                     # RSpec test suite
│   ├── enterprise/           # EE-specific specs
│   ├── factories/            # FactoryBot factories
│   └── support/              # Test helpers
├── docker/                   # Docker configuration
├── deployment/               # Systemd service files
└── public/                   # Static assets
```

### Key Architectural Patterns

1. **Service Objects**: Business logic lives in `app/services/` organized by domain
2. **Policy Objects**: Authorization via Pundit in `app/policies/`
3. **Pub/Sub**: Wisper gem for decoupled event handling
4. **Background Jobs**: Sidekiq for async processing
5. **Enterprise Modularity**: EE code extends OSS via `prepend_mod_with` / `include_mod_with`

### Enterprise Edition Integration

The `enterprise/` directory overlays the OSS codebase:

- **Models**: Extend via concerns in `enterprise/app/models/enterprise/concerns/`
- **Controllers**: Override or extend via `enterprise/app/controllers/enterprise/`
- **Routes**: EE routes conditionally loaded in `config/routes.rb`
- **Specs**: Mirror OSS structure under `spec/enterprise/`

**Enterprise check in code:**
```ruby
if ChatwootApp.enterprise?
  # Enterprise-only feature
end
```

## Build / Test / Lint Commands

### Setup
```bash
# Ruby setup
rbenv install $(cat .ruby-version)
eval "$(rbenv init -)"
bundle install

# Node setup
pnpm install
```

### Development Server
```bash
# Option 1: Overmind (recommended)
overmind start -f Procfile.dev

# Option 2: pnpm script
pnpm dev

# Option 3: Foreman
foreman start -f ./Procfile.dev
```

**Procfile.dev processes:**
- `backend`: Rails server on port 3000
- `worker`: Sidekiq job processor
- `vite`: Vite dev server for HMR

### Testing

**Ruby (RSpec):**
```bash
# All tests
bundle exec rspec

# Specific file
bundle exec rspec spec/path/to/file_spec.rb

# Specific line
bundle exec rspec spec/path/to/file_spec.rb:LINE_NUMBER

# Enterprise tests
bundle exec rspec spec/enterprise/
```

**JavaScript/Vue (Vitest):**
```bash
# Run once
pnpm test

# Watch mode
pnpm test:watch

# With coverage
pnpm test:coverage
```

### Linting

**Ruby:**
```bash
bundle exec rubocop -a        # Auto-fix
bundle exec rubocop           # Check only
```

**JavaScript/Vue:**
```bash
pnpm eslint                   # Check
pnpm eslint:fix               # Auto-fix
```

**SCSS:**
```bash
scss-lint
```

### Build for Production

```bash
# Vite build
bin/vite build

# SDK build (separate)
BUILD_MODE=library bin/vite build

# Rails assets
bin/rails assets:precompile
```

## Code Style Guidelines

### Ruby
- **Max Line Length**: 150 characters
- **Style**: RuboCop enforced with custom cops in `rubocop/`
- **Class Format**: Use compact style `class Foo::Bar` not nested modules
- **Documentation**: Disabled (no YARD required)
- **Frozen String**: Disabled
- **Hash Syntax**: No mixed keys, shorthand disabled

### Vue/JavaScript
- **ESLint**: Airbnb base + Vue 3 recommended
- **Component Names**: PascalCase
- **Events**: camelCase
- **API Style**: Composition API with `<script setup>` mandatory
- **Block Order**: `[script, template, style]`
- **i18n**: No bare strings in templates (enforced by ESLint)

### Styling (Tailwind CSS)
**CRITICAL**: Tailwind utility classes ONLY
- ❌ No custom CSS
- ❌ No scoped CSS (`<style scoped>`)
- ❌ No inline styles (`:style` binding)
- ✅ Always use Tailwind utility classes
- **Colors**: Use CSS variables from `tailwind.config.js` (radix colors)
- **Icons**: Use `icon-{collection}-{name}` classes via @egoist/tailwindcss-icons

## Testing Strategy

### RSpec Configuration
- **Framework**: RSpec Rails with test-prof for optimization
- **Fixtures**: FactoryBot with `let_it_be` and `before_all` for performance
- **Matchers**: Shoulda Matchers for Rails
- **Mocking**: WebMock for HTTP, MockRedis for Redis
- **Policy**: Pundit RSpec matchers
- **Sidekiq**: `sidekiq/testing` inline mode

### Test Organization
```
spec/
├── models/              # Unit tests
├── controllers/         # Controller specs
├── services/            # Service object specs
├── jobs/                # Background job specs
├── policies/            # Authorization specs
├── enterprise/          # EE-specific specs (mirrors OSS)
├── factories/           # Test data factories
└── support/             # Shared contexts, helpers
```

### Frontend Testing
- **Framework**: Vitest with jsdom environment
- **Utils**: @vue/test-utils
- **Coverage**: v8 provider with lcov output
- **Location**: `app/**/*.{test,spec}.js`

### Writing Tests
- Specs should be avoided unless explicitly requested
- Use `with_modified_env` helper instead of stubbing `ENV` directly
- In parallel/reloading environments: compare `error.class.name` instead of class equality

## Database & Migrations

### PostgreSQL Requirements
- Version 16+ with pgvector extension (for AI features)
- Pool size: Dynamic based on Sidekiq concurrency or Rails max threads
- Statement timeout: 14 seconds (configurable)

### Key Models
- **Account**: Multi-tenancy root
- **User**: Authentication entity
- **Contact**: Customer/end-user
- **Conversation**: Core chat entity
- **Message**: Individual messages
- **Inbox**: Channel configuration

### Migrations
- Use `activerecord-import` for bulk operations
- Database triggers via `hairtrigger` gem
- Run with: `bin/rails db:migrate`

## Environment Configuration

### Required Variables
```bash
SECRET_KEY_BASE=              # Generate with `rails secret`
FRONTEND_URL=                 # Your app URL
REDIS_URL=                    # Redis connection
POSTGRES_HOST/USER/PASSWORD   # Database credentials
```

### Optional/Feature Flags
```bash
# MFA/Encryption (required for 2FA)
ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY=
ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY=
ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT=

# AI Features
OPENAI_API_KEY=

# Channel Integrations
FB_APP_ID/FB_APP_SECRET       # Facebook
TWITTER_CONSUMER_KEY/SECRET   # Twitter
SLACK_CLIENT_ID/SECRET        # Slack

# Storage
ACTIVE_STORAGE_SERVICE=s3     # or local, azure, gcs
S3_BUCKET_NAME=...

# Monitoring
SENTRY_DSN=...
DD_TRACE_AGENT_URL=...        # Datadog
```

See `.env.example` for complete list.

## API Architecture

### API Versions
- **V1**: Main API (stable)
- **V2**: Reports API (evolving)
- **Platform API**: Account management
- **Public API**: Contact-facing endpoints
- **Widget API**: Embeddable chat

### Authentication
- **Dashboard**: Devise token auth via `Authorization` header
- **Widget**: Contact-based tokens
- **Platform**: API access tokens

### Key Endpoints
```ruby
# Auth
POST /auth/sign_in
DELETE /auth/sign_out

# Conversations
GET /api/v1/accounts/:account_id/conversations
POST /api/v1/accounts/:account_id/conversations/:id/toggle_status

# Messages
GET /api/v1/accounts/:account_id/conversations/:conversation_id/messages
POST /api/v1/accounts/:account_id/conversations/:conversation_id/messages

# Widget
POST /api/v1/widget/messages
GET /api/v1/widget/conversations
```

## Deployment

### Docker (Development)
```bash
docker-compose up
```
Services: rails, sidekiq, vite, postgres, redis, mailhog

### Docker (Production)
See `docker-compose.production.yaml`

### Traditional Deployment
- Systemd services in `deployment/`
- Capistrano via `Capfile`
- Heroku one-click deploy button available

### Background Jobs
Sidekiq web UI available at `/monitoring/sidekiq` (super_admin only)

## Security Considerations

1. **Encryption**: Active Record encryption for MFA/secrets
2. **CORS**: Configured via `rack-cors`
3. **Rate Limiting**: Rack Attack for throttling
4. **Input Validation**: Strong params, validation in models
5. **Authorization**: Pundit policies on all resources
6. **Secrets**: Environment-based, never commit credentials

## Internationalization (i18n)

### Backend
- Location: `config/locales/en.yml`
- Only modify `en.yml` (other languages via Crowdin)

### Frontend
- Location: `app/javascript/dashboard/i18n/en.json`
- Flat structure, namespaced by feature
- Use `t('key.path')` helper, never bare strings

## Git Workflow

### Branching Model (Git Flow)
- **develop**: Base branch for features
- **master**: Stable releases
- **feature/***: Feature branches
- **hotfix/***: Production fixes

### Commit Messages
Prefer Conventional Commits:
```
feat(scope): description
fix(scope): description
refactor(scope): description
docs(scope): description
```

### Pre-push Hooks
- Runs `bin/validate_push`
- ESLint fixes on staged files
- No Claude references in commits

## Development Best Practices

### Code Philosophy
- **MVP First**: Ship happy path, iterate on edge cases
- **Minimal Code**: Least change to achieve goal
- **Clarity > Cleverness**: Readable over abstract
- **Remove Dead Code**: Delete unused code immediately
- **One Version**: No backup/multiple implementations

### Error Handling
- Use custom exceptions in `lib/custom_exceptions/`
- Don't over-defensive program
- Let errors bubble to appropriate handler

### Performance
- Use `find_each` for large collections
- Background jobs for slow operations
- Database indexes on query paths
- N+1 prevention with `bullet` gem

### Code Review Checklist
- [ ] Tailwind classes only (no custom CSS)
- [ ] i18n strings (no bare text)
- [ ] Composition API with `<script setup>`
- [ ] RuboCop passes
- [ ] ESLint passes
- [ ] Enterprise compatibility checked
- [ ] No console.log in production code

## Troubleshooting

### Common Issues

**Ruby version mismatch:**
```bash
rbenv install $(cat .ruby-version)
eval "$(rbenv init -)"
```

**Bundle install fails:**
```bash
bundle config set --local path 'vendor/bundle'
bundle install
```

**Node modules issues:**
```bash
rm -rf node_modules pnpm-lock.yaml
pnpm install
```

**Database connection:**
- Check PostgreSQL is running
- Verify credentials in `.env`
- Run: `bin/rails db:create db:migrate`

**Sidekiq not processing jobs:**
- Check Redis connection
- Verify `SIDEKIQ_CONCURRENCY` setting
- Check Sidekiq web UI for retries/dead jobs

## Resources

- **Documentation**: https://www.chatwoot.com/help-center
- **API Docs**: `/swagger` endpoint locally
- **Discord**: https://discord.gg/cJXdrwS
- **Status**: https://status.chatwoot.com
