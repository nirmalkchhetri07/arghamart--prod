# Node.js to Rails / Spree cheatsheet

Use this as a map from Express vocabulary to this repository. Rails paths below are relative to `backend/` unless a root path is stated.

| Node.js concept | Rails / Spree equivalent | Where it lives here | What it does |
|---|---|---|---|
| `app.get(...)`, Express routers | Rails routes / mounted engine | `config/routes.rb:1-139` | Routes point at controller actions; Spree supplies many routes through its mounted engine. |
| Handler functions | Controller actions | `app/controllers/` | An action reads request state, invokes domain behavior, and renders JSON or HTML. Many stock Spree controllers are in gems. |
| `express.Router()` grouping | Rails `namespace`, `resources`, engine mount | `config/routes.rb:24-115,125` | Namespaces provide URL and Ruby module prefixes; `mount Spree::Core::Engine` exposes stock routes. |
| Auth middleware, `req.user`, JWT/session | Devise, Spree API authentication and API keys/tokens | `config/routes.rb:3-14,126-127`; `config/initializers/devise.rb`; `app/models/spree/user.rb`, `app/models/spree/admin_user.rb`; `lib/spree/authentication_helpers.rb` | Devise handles account/session concerns; Store API auth is provided by Spree; API key/token details are in Spree code. Exact engine internals are unverified here. |
| Authorization / roles | CanCanCan abilities and Spree permission sets | `config/initializers/spree.rb:44-59,111-118`; `app/models/spree/role_permissions.rb`; `app/models/spree/permission_sets/` | Authentication identifies the actor; abilities answer whether that actor may perform an action. |
| CORS, Helmet, body parser | Rack middleware + Rails/Spree config | `config/initializers/cors.rb`; `config/initializers/content_security_policy.rb`; `config/application.rb`; `config/initializers/spree.rb:38-42` | Rack middleware runs around the Rails app; CORS and CSP are configured here. Rails parses request bodies; Spree caps API body size. |
| `express-rate-limit` | Spree API `rate_limit` controller concern; Rack::Attack is not configured | `app/controllers/spree/api/v3/store/oauth_controller.rb:39`; `Gemfile`; `config/initializers/` | OAuth applies Spree's login rate-limit setting. No `rack-attack` gem or initializer was found. Add a Rack::Attack gem and initializer if general endpoint throttling is needed. |
| Sequelize / Mongoose / Prisma | ActiveRecord models | `app/models/`; stock models come from Spree gems | Models represent database rows and associations; custom code decorates Spree models. |
| ORM migrations | ActiveRecord migrations and schema snapshot | `db/migrate/`; `db/schema.rb` | Migrations evolve tables; schema is Rails' current database structure. Custom examples include `db/migrate/20260929000001_add_manual_qr_to_spree_payments.rb` and `db/migrate/20261001000005_create_offline_payment_details.rb`. |
| Joi / Zod input checks | Strong parameters + model validations | Controllers in `app/controllers/`; validations in `app/models/` | Strong params whitelist writable fields; model validations protect persisted data. Spree controllers also validate API contracts. |
| `services/`, utility modules | Service objects, model/domain methods, concerns, `lib/` | `app/` and `lib/`; e.g. `app/models/spree/nepal_geography.rb`, `lib/spree/authentication_helpers.rb` | Rails has no mandatory service directory convention; this app uses domain code and concerns rather than a large `app/services/` tree. |
| Bull / Agenda | ActiveJob backed by Solid Queue | `app/jobs/`; `config/application.rb:63-80`; `config/queue.yml` | Jobs are Ruby classes enqueued with `perform_later`; this app stores/runs them via Solid Queue. |
| `dotenv`, `config.js`, secrets | Rails `config/`, environment variables, credentials | `config/`; `backend/.env`; root `.env.production` (untracked; template `.env.production.example`) | Environment-specific settings and secret values configure the process. Never commit values from env files. |
| `package.json` / npm dependencies | `Gemfile` / Bundler | `Gemfile`, `Gemfile.lock` | Gems are Ruby packages; `bundle install` resolves the locked dependency set. |
| Node REPL / scripts | `rails console`, `rails runner`, Rake tasks | `bin/rails`; `lib/tasks/`; `lib/tasks/storage.rake` | Console is interactive app context; runner executes a Ruby expression/file; Rake tasks are named operational commands. |
| Jest / Mocha | RSpec (not Minitest in this app) | `spec/` | Specs cover models, requests, jobs, and mailers; examples include `spec/requests/spree/manual_qr_proofs_spec.rb`. |
| Email templates | Action Mailer + view templates | `app/mailers/`; `app/views/`; `config/environments/production.rb` | Mailer methods construct messages; matching templates render content. SMTP is environment-configured; Resend is supported through SMTP settings, not a Resend-specific gem. |
| Multer / S3 uploads | ActiveStorage attachments and services | `app/models/spree/payment_decorator.rb:13-19`; `config/storage.yml`; `config/environments/production.rb:21-34` | `has_one_attached` associates a blob; local disk or S3-compatible Cloudflare R2 stores bytes. |
| Webhook consumers / emitters | Spree webhook models/events and delivery jobs; custom manual-QR alert webhook | `config/initializers/spree.rb:193-210`; Spree webhook code in gems; `app/jobs/spree/manual_qr_alert_job.rb` | Spree event subscriptions/deliveries are engine-owned; the custom QR alert job posts to an optional configured endpoint. |
| HTML templates / JSX | ERB views and partials; API serializers | `app/views/`; `app/serializers/` | ERB renders server HTML; serializers shape JSON. The separate Next.js storefront lives at root `apps/storefront/`. |

### Small translation

```js
// Express
router.post('/proof', requireUser, upload.single('proof'), handler)
```

```ruby
# Rails: route -> controller action -> permitted params / model attachment
post :proof, to: 'carts/manual_qr_proofs#create'
```

Rails doesn't require every action to call `next()`: returning a `render`, `redirect_to`, or `head` ends the response. For this project's application-specific conventions see [`backend/CLAUDE.md`](../../backend/CLAUDE.md).
