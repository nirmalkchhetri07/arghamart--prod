# How to find things

Run Rails commands in the backend container. From repo root, the direct Docker form is `docker compose -f docker-compose.dev.yml exec web ...`; `pnpm spree ...` wraps common operations where noted in root `CLAUDE.md`. Do not run commands against production unless you intentionally select the production compose file and environment.

## Find an endpoint

```bash
docker compose -f docker-compose.dev.yml exec web bin/rails routes | grep -E 'products|orders|payments'
docker compose -f docker-compose.dev.yml exec web bin/rails routes -c Spree::Api::V3::Store::ProductsController
```

Rails CLI accepts `-c`/`--controller` to filter by controller. `rails routes` could not be read from the available Docker session while these docs were written; the custom declarations are visible in `backend/config/routes.rb`, while engine route details are marked unverified.

## Identify the controller/action

Routes display HTTP verb, path, helper name, and controller#action. Example source declaration: `post :proof, to: 'carts/manual_qr_proofs#create'` at `backend/config/routes.rb:84-90`. For a mounted engine, route output may list an engine route/controller from the gem. `resources :orders` conventionally maps `GET /orders/:id` to `show`, `PATCH /orders/:id` to `update`, etc.; only explicit custom actions are listed locally.

## Find auth and permissions

- Admin login/session route setup: `backend/config/routes.rb:3-14`; Devise settings: `backend/config/initializers/devise.rb`.
- Role definitions and Spree permission registration: `backend/config/initializers/spree.rb:44-59,111-118`.
- Permission behavior: `backend/app/models/spree/role_permissions.rb` and `backend/app/models/spree/permission_sets/`.
- Explicit action check example: `authorize! :manage, Spree::OauthProvider` in `backend/app/controllers/spree/admin/oauth_providers_controller.rb`.
- Store API auth helpers/custom OAuth: `backend/lib/spree/authentication_helpers.rb`, `backend/app/controllers/spree/api/v3/store/oauth_controller.rb`; remaining Store API auth is Spree engine behavior.

## Inspect a model's fields

```bash
rtk rg -n 'create_table "spree_payments"|create_table "spree_orders"' backend/db/schema.rb
docker compose -f docker-compose.dev.yml exec web bin/rails console
```

In console, query `Spree::Payment.column_names`, `Spree::Order.columns`, or `Spree::Payment.reflect_on_all_associations`. For pending schema changes inspect `backend/db/migrate/`; do not edit `schema.rb` directly. Exact live schema can differ until migrations run.

## Find Spree overrides

```bash
rtk rg -n 'Decorator|prepend|include|Spree\.dependencies|Spree\.subscribers' backend/app backend/config
```

This app's prepend registrations are explicit in `backend/config/initializers/spree.rb:44-80`. Model extensions commonly live in `backend/app/models/spree/*_decorator.rb`; controller extensions end in `_controller_decorator.rb`. Spree project's local instructions prefer event subscribers for side effects, dependency swaps when replacing a service, and decorators for structural model changes (`backend/CLAUDE.md`).

## Read Spree source inside Docker

```bash
docker compose -f docker-compose.dev.yml exec web bundle show spree_core
docker compose -f docker-compose.dev.yml exec web bundle show spree_api
```

Then inspect files below the printed gem path with `sed`/`rg` from a shell in the same container. `bundle show` on the host may fail because the host intentionally does not install the project's Ruby bundle.

## Run common commands in containers

Development:

```bash
docker compose -f docker-compose.dev.yml exec web bin/rails console
docker compose -f docker-compose.dev.yml exec web bin/rails runner 'puts Spree::Product.count'
docker compose -f docker-compose.dev.yml exec web bin/rails db:migrate
docker compose -f docker-compose.dev.yml exec web bundle exec rspec spec/requests/spree/manual_qr_proofs_spec.rb
```

Production is different and can change live data. Examples for an intentional inspection:

```bash
docker compose -f docker-compose.prod.yml --env-file .env.production exec web bin/rails routes
docker compose -f docker-compose.prod.yml --env-file .env.production logs -f web
```

Dev compose uses Postgres service `postgres`, local ActiveStorage volume and Mailpit; production compose uses persistent Postgres/storage volumes. The production env file is untracked and must not be printed or committed.

## Conventions worth remembering

- `Spree::Order` is singular class name; its table is `spree_orders`; controller is usually `OrdersController`; path is usually `/orders`.
- `before_action` is similar to controller middleware and runs before selected actions; e.g. `before_action :find_order!`.
- Concerns are reusable modules mixed into controllers/models; inspect `app/controllers/concerns/`.
- Strong params whitelist input; don't assume request JSON is automatically safe to mass assign.
- `render json:` returns API data; `render :template`/implicit render returns a view; `redirect_to` issues a redirect.
- `Module#prepend` wraps a class method lookup chain and is how this app extends engine classes. It differs from editing gem source.
- Spree API IDs are prefixed IDs; do not expose raw integer IDs in custom API responses.
- Migration files are history; `schema.rb` is the current generated snapshot.

## Glossary

| Rails term | Node.js equivalent |
|---|---|
| Route | Router path/method registration |
| Controller/action | Handler function |
| Rack middleware | Express middleware around the app |
| Model / ActiveRecord | ORM model/entity |
| Migration | Database migration |
| Strong parameters | Request schema allowlist |
| Concern | Shared mixin/helper behavior |
| Job / ActiveJob | Queue worker task |
| Mailer | Email composition and delivery module |
| View / partial | Server template / reusable template component |
| Serializer | JSON response mapper |
| Initializer | Application startup registration/configuration |
| Engine | Mounted framework/plugin app with routes and code |
| Decorator / `prepend` | Runtime extension/wrapper of a library class |
| Rake task | Named CLI task/script |
| `rails console` | App-aware REPL |
