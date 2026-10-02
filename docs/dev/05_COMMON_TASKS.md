# Common development tasks

All paths are relative to `backend/`. Follow `backend/CLAUDE.md`: prefer Spree events for side effects, dependency swaps for replaceable services, and decorators for model structure. Run Rails/Bundler commands inside the dev container.

## Add a Store API endpoint

1. Add an additive route in `config/routes.rb` within the matching `namespace :api` block. Use a controller action under `app/controllers/spree/api/v3/store/`.
2. Implement the action in a namespaced controller. Reuse Spree auth/context behavior, whitelist inputs, and return the expected Store API JSON/error envelope.
3. If new response fields are needed, extend/add the serializer under `app/serializers/spree/api/v3/` rather than hand-building inconsistent JSON.
4. Add/update a request spec under `spec/requests/spree/store/` or a feature-specific request spec.
5. Inspect the route: `docker compose -f docker-compose.dev.yml exec web bin/rails routes | grep endpoint_fragment`.

Existing example: Nepal provinces at `config/routes.rb:81-83` and `app/controllers/spree/api/v3/store/nepal/provinces_controller.rb`.

## Add a database field to a Spree model

1. Generate a migration inside Docker: `docker compose -f docker-compose.dev.yml exec web bin/rails generate migration AddFooToSpreeOrders foo:string`.
2. Edit the generated `db/migrate/<timestamp>_add_foo_to_spree_orders.rb`; use the actual table name from `db/schema.rb`.
3. Run `... exec web bin/rails db:migrate`; Rails updates `db/schema.rb`.
4. Add a decorator only if model behavior/association must change: `app/models/spree/order_decorator.rb`, registered using the local pattern in `config/initializers/spree.rb`.
5. Update strong params, serializer, and specs where the field is accepted or returned.

For application-owned tables, consider `bin/rails generate model` instead. Never edit gem source or manually edit `schema.rb`.

## Add a validation

1. For a custom model use its file in `app/models/`; for a Spree model add it in a model decorator's `self.prepended(base)` block (example `app/models/spree/payment_decorator.rb:13-19`).
2. Decide whether the validation applies to old/incomplete records; conditional validations often use `if:`.
3. Whitelist input in the relevant controller if the field is client-writable.
4. Add a model spec in `spec/models/` and request coverage when the API behavior matters.

## Protect a route

1. For admin UI, use Spree/Devise admin authentication and CanCan authorization. Define permission through `app/models/spree/permission_sets/` or `role_permissions.rb`; add `authorize!` in the controller for a custom action.
2. For Store API customer-owned data, use Spree order-token/customer auth and explicitly authorize the target order. See `app/controllers/spree/api/v3/store/manual_qr_proofs_controller.rb`.
3. Avoid inventing a second session/JWT scheme when Spree provides the API auth contract.
4. Add request specs for anonymous, unauthorized, and permitted callers.

## Add rate limiting

Current state: this repo has a Spree API rate limit for OAuth login at `app/controllers/spree/api/v3/store/oauth_controller.rb:39`; no Rack::Attack dependency or initializer was found.

For general endpoint/IP throttling, add `rack-attack` to `Gemfile`, configure throttles/blocklists in a new `config/initializers/rack_attack.rb`, insert/configure the middleware in `config/application.rb`, and add request specs. Choose proxy/IP handling carefully behind the production proxy. For API login, continue using the Spree API config limit rather than duplicating it.

## Add a background job

1. Create `app/jobs/spree/my_job.rb` inheriting `ApplicationJob` (or Spree's job base where appropriate).
2. Enqueue with `MyJob.perform_later(id)`; pass stable IDs rather than serialized ActiveRecord objects when practical.
3. Ensure idempotency and log failure context. Solid Queue is configured in `config/application.rb` and `config/queue.yml`; production workers run in Puma by default.
4. Add `spec/jobs/spree/my_job_spec.rb`. For recurring work, configure `config/recurring.yml` and verify the schedule against the installed Solid Queue version.

Existing examples: `app/jobs/spree/manual_qr_alert_job.rb` and `manual_qr_expire_orders_job.rb`.

## Add an admin permission

1. Define or extend a permission set in `app/models/spree/permission_sets/`.
2. Add its named set to `Spree::RolePermissions::SETS` / role categories in `app/models/spree/role_permissions.rb`.
3. Register/assign role sets in `config/initializers/spree.rb`; if adding a persisted permission-set name, add a migration and update the matching allowlist.
4. Add controller `authorize!` checks and gate navigation visibility with `can?` so menu visibility and endpoint access agree.
5. Update `app/views/spree/admin/roles/` and its Stimulus controller only if the role editor needs UI changes.
6. Add model permission specs and request specs for denied/allowed roles.

Read the existing patterns in `app/models/spree/permission_sets/`, `app/models/spree/role_permissions.rb`, and `spec/models/spree/permission_sets/` first.

## Add a webhook event

For Spree's event system (side effect/integration):

1. Emit/publish the event from the appropriate domain transition using Spree's event API; prefer a subscriber over a callback that performs network I/O.
2. Create `app/subscribers/spree/my_subscriber.rb` inheriting `Spree::Subscriber`, declare `subscribes_to`, and register it in `config/initializers/spree.rb` after initialization.
3. Put outbound delivery in an ActiveJob; validate destination, set timeouts, handle retries/idempotency, and avoid logging secrets.
4. Add subscriber/job specs and document payload shape for the receiver.

The subscriber directory is recommended by `backend/CLAUDE.md` but does not currently exist in this app; create it only when implementing this feature. For an n8n manual-QR alert specifically, use the existing `preferred_alert_webhook_url` setting and `app/jobs/spree/manual_qr_alert_job.rb` rather than adding a duplicate event path.
