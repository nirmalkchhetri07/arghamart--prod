# Project map

Root-level `backend/` is the Rails API/admin application. `apps/storefront/` is a separate Next.js client. Directory statuses: **Rails default** means Rails-created structure; **Spree** means engine/gem-provided behavior; **Custom** means app-specific additions.

## Root and deployment files

| Path | Purpose / Node analogy | Origin |
|---|---|---|
| `backend/Gemfile`, `backend/Gemfile.lock` | Ruby package manifest and resolved dependency lock, like `package.json` + lockfile | Rails default + project choices |
| `backend/config/` | Application config and route composition, like `config/` plus server bootstrap | Rails default + custom initializers |
| `backend/db/` | Migrations, schema snapshot and seeds | Rails default; Spree/custom migrations |
| `backend/app/` | Main application code, roughly `src/` | Rails default conventions + custom features |
| `backend/spec/` | RSpec tests, like Jest/Mocha suites | Custom project suite |
| `backend/lib/` | Shared support and Rake tasks, like `lib/` or scripts | Rails default + custom |
| `backend/Dockerfile` | Container build | Custom deployment |
| `docker-compose.dev.yml` | Dev services, bind mounts, Postgres and Mailpit | Custom deployment |
| `docker-compose.prod.yml` | Production web + Postgres + persistent volumes | Custom deployment |
| `.env.production.example` | Redacted variable names and comments; live `.env.production` is untracked | Custom deployment |
| `apps/storefront/` | Next.js storefront client talking to Store API | Separate app |

## `backend/app/`

```text
app/
├── controllers/       # HTTP actions, Rails analogy to Express routers/handlers
├── models/            # ActiveRecord/domain objects, Spree extensions, payment logic
├── jobs/              # ActiveJob classes executed by Solid Queue
├── mailers/           # Email composition
├── serializers/       # API response representation extensions
├── views/             # ERB HTML/email templates and partials
├── helpers/           # View formatting/presentation helpers
├── javascript/        # Admin Stimulus controllers (small frontend behaviors)
└── assets/            # CSS/assets; Tailwind/admin styles
```

All except stock Rails scaffolding are custom app directories containing a mix of framework conventions and **custom** additions. Spree's controller/model/view implementations are primarily in gems; local `spree/` files extend them.

### Custom hotspots

| Path | Why you'll visit |
|---|---|
| `app/controllers/spree/api/v3/store/` | Store API extensions: OAuth, Nepal provinces, manual QR proof upload, cart behavior |
| `app/controllers/spree/admin/` | Admin actions/decorators: QR review, offline payment, Nepal fees/geography, roles, OAuth provider config |
| `app/controllers/concerns/spree/api/v3/store/` | Shared API error handling for storage failures |
| `app/models/spree/payment_method/` and `payment_sessions/` | QR, eSewa, Khalti custom payment methods and their session behavior |
| `app/models/spree/*_decorator.rb` | `Module#prepend` extensions to Spree models |
| `app/models/spree/permission_sets/`, `role_permissions.rb` | Custom staff/manager role model and permission-set behavior |
| `app/jobs/spree/` | QR proof alert delivery and QR order expiration |
| `app/mailers/spree/` and `app/views/spree/manual_qr_mailer/` | Custom QR proof notification email |
| `app/serializers/spree/api/v3/` | Extra API fields such as payment proof URL/status |
| `app/views/spree/admin/` | Custom admin panels and partial overrides |

## `backend/config/`

| Path | Purpose / analogy | Origin |
|---|---|---|
| `config/routes.rb` | URL-to-controller map; mounts Spree engine and adds custom routes | Rails + custom |
| `config/application.rb` | Process-wide Rails boot configuration, like app bootstrap | Rails + custom Solid Queue/jobs auth |
| `config/initializers/spree.rb` | Spree registration/configuration, dependencies, roles, navigation, payment methods | Spree config + substantial custom work |
| `config/initializers/devise.rb` | Authentication library settings | Devise/Rails |
| `config/initializers/cors.rb` | CORS Rack middleware policy | Custom |
| `config/initializers/content_security_policy.rb` | CSP policy, roughly Helmet headers | Rails + custom policy |
| `config/initializers/filter_parameter_logging.rb` | Redacts sensitive request fields from logs | Rails default/config |
| `config/database.yml` | Database connection settings | Rails default + Postgres |
| `config/storage.yml` | ActiveStorage local/Amazon-compatible services | Rails + custom R2 service |
| `config/queue.yml`, `config/recurring.yml` | Solid Queue worker pools and recurring tasks | Solid Queue + custom schedules |
| `config/environments/{development,production,test}.rb` | Runtime settings per environment | Rails + project |
| `config/locales/en.yml` | UI and domain translations | Rails + custom strings |
| `config/puma.rb` | Puma web server config | Rails default/project |

## `backend/db/`, `lib/`, `spec/`

`db/migrate/` contains both Spree-generated migrations and custom changes. Custom feature migrations include `20260929000001_add_manual_qr_to_spree_payments.rb`, `20261001000005_create_offline_payment_details.rb`, `20261001000006_create_cash_physical_payment_method.rb`, and the Nepal geography migrations. `db/schema.rb` is the current table snapshot; table names/fields make it the equivalent of your ORM schema view. `db/seeds.rb` initializes data.

`lib/tasks/storage.rake` is an operational storage task; `lib/spree/authentication_helpers.rb` is shared auth support. `spec/requests/` tests HTTP behavior; `spec/models/`, `spec/jobs/`, and `spec/mailers/` test their matching layers. Spree engine specs and implementation aren't necessarily in this repository.

## Runtime shape

Development compose runs Postgres, Mailpit, and one `web` container; Puma runs Solid Queue in-process by default. Production compose has `postgres` and `web`; R2 and SMTP providers are selected/configured through environment variables. No separate Redis service is needed for the Solid stack.
