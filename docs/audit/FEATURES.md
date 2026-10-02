# Backend Feature Inventory: arghamart

**Project:** arghamart  
**Audit Date:** October 2, 2026  
**Scope:** Spree Commerce Backend (`backend/`)  

---

## 1. Storefront & Checkout

| Feature | Description | Key Files | Status | Notes or Risks |
| :--- | :--- | :--- | :--- | :--- |
| **Cart Pipeline & Order Completion** | Stock Spree 5.6 Store API cart management, line item addition, and checkout state transitions. | `config/routes.rb`<br>`app/controllers/spree/api/v3/store/carts_controller_decorator.rb` | Working | Relies on stock Spree engine hooks. |
| **Address Handling & Validations** | Standardized address collection with custom validations forcing phone presence & format for Nepal checkouts. | `app/models/spree/address_decorator.rb` | Working | Zip code required flag disabled globally for Nepal market compatibility. |
| **Nepal Geography Dropdowns API** | REST API providing structured Nepal provinces and districts list for storefront address selectors. | `app/controllers/spree/api/v3/store/nepal/provinces_controller.rb`<br>`app/models/spree/nepal_geography.rb` | Working | Includes pre-seeded 7 provinces and 77 districts. |

---

## 2. Product & Catalog Management

| Feature | Description | Key Files | Status | Notes or Risks |
| :--- | :--- | :--- | :--- | :--- |
| **Product & Variant Catalog** | Spree multi-variant catalog, option types/values, taxons, taxonomies, and product publication on channels. | Core Spree Models | Working | Stock Spree functionality. |
| **Database Product Search** | Default product search query processing using PostgreSQL `pg_trgm` extension. | `db/migrate/20260317146046_enable_pg_trgm_extension.spree.rb` | Working | Meilisearch configuration is available in Docker but disabled by default. |

---

## 3. Payments & Custom Payment Flows

| Feature | Description | Key Files | Status | Notes or Risks |
| :--- | :--- | :--- | :--- | :--- |
| **Manual QR Payment Flow** | Customers view store QR code, upload screenshot proof (+ optional txn ID), and submit for admin verification. | `app/models/spree/payment_method/manual_qr.rb`<br>`app/models/spree/payment_sessions/manual_qr.rb`<br>`app/controllers/spree/api/v3/store/manual_qr_proofs_controller.rb`<br>`app/controllers/spree/api/v3/store/carts/manual_qr_proofs_controller.rb` | Working | Requires rate limiting protection (`SEC-02`) and pessimistic concurrency locking (`LOG-01`). |
| **Manual QR Admin Review** | Admins inspect proof screenshot, review duplicate checksum/txn alerts, and execute Approve or Reject actions. | `app/controllers/spree/admin/payments_controller_decorator.rb`<br>`app/views/spree/admin/payment_methods/custom_form_fields/_manual_qr.html.erb` | Working | Displays signed pre-signed ActiveStorage URL expiring in 5 minutes. |
| **Automated QR Order Expiration** | Background recurring job that cancels pending QR orders exceeding configured timeout hours (default 24h) and releases stock. | `app/jobs/spree/manual_qr_expire_orders_job.rb`<br>`config/recurring.yml` | Working | Configured via `order_timeout_hours` preference. |
| **QR Proof Upload Alerting** | Triggers email notifications and optional webhook payloads to external systems (Slack/n8n) when proof uploaded. | `app/jobs/spree/manual_qr_alert_job.rb`<br>`app/mailers/spree/manual_qr_mailer.rb` | Working | Sends alerts to configured emails or store staff. |
| **eSewa ePay v2 Gateway** | Redirect-based online payment integration with server-to-server transaction status verification. | `app/models/spree/payment_method/esewa.rb`<br>`app/models/spree/payment_sessions/esewa.rb`<br>`spec/requests/spree/payment_sessions/esewa_spec.rb` | Working | HMAC-SHA256 signature verification implemented; redirect payload validated server-side. |
| **Khalti ePayment v2 Gateway** | Initiates Khalti payment URL and validates payment status via server-to-server lookup API. | `app/models/spree/payment_method/khalti.rb`<br>`app/models/spree/payment_sessions/khalti.rb` | Working | Converts NPR to paisa (x100) and matches `pidx` explicitly. |

---

## 4. Offline & Cash Order Handling

| Feature | Description | Key Files | Status | Notes or Risks |
| :--- | :--- | :--- | :--- | :--- |
| **Cash on Delivery (COD)** | Allows orders to complete in `balance_due` state; payment capture occurs automatically when shipment is marked delivered. | `db/migrate/20260916010000_disable_auto_capture_for_cash_on_delivery.rb`<br>`app/models/spree/shipment_decorator.rb` | Working | `mark_as_delivered!` captures pending Check/COD payments automatically. |
| **Shipment Delivery Tracking** | Adds `delivered_at` timestamp and admin action to shipments without altering Spree's core shipment state machine. | `app/models/spree/shipment_decorator.rb`<br>`app/controllers/spree/admin/shipments_controller_decorator.rb`<br>`app/helpers/spree/admin/shipment_delivery_helper.rb` | Working | Custom `mark_as_delivered` member route. |

---

## 5. Admin Roles & Permissions

| Feature | Description | Key Files | Status | Notes or Risks |
| :--- | :--- | :--- | :--- | :--- |
| **Custom Permission Sets** | Modular CanCan permission sets mapping database-defined roles to granular admin UI capabilities. | `app/models/spree/role_permissions.rb`<br>`app/models/spree/permission_sets/staff_order_desk.rb`<br>`app/models/spree/permission_sets/additional_admin_access.rb` | Working | Includes `StaffOrderDesk`, `GeographyManagement`, `IntegrationManagement`, and `InvitationManagement`. |
| **Role Permissions UI Controller** | Admin interface for managing and assigning permission sets to roles. | `app/controllers/spree/admin/roles_controller_decorator.rb`<br>`app/javascript/controllers/role_permissions_controller.js` | Working | Integrates with Spree Admin Turbo UI. |
| **Phone-Based Customer Search in Admin** | Phone lookup helper in New Order admin screen enabling customer resolution by Nepali phone number. | `app/controllers/spree/admin/orders_controller_decorator.rb`<br>`app/controllers/spree/admin/users_controller_decorator.rb` | Working | Normalizes Nepali phone numbers (stripping +977 prefix). |

---

## 6. Social Login & External Integrations

| Feature | Description | Key Files | Status | Notes or Risks |
| :--- | :--- | :--- | :--- | :--- |
| **Social Login (Google, FB, GitHub)**| OAuth verification and identity linking for customer accounts using encrypted provider credentials. | `app/controllers/spree/api/v3/store/oauth_controller.rb`<br>`app/models/spree/oauth_provider.rb`<br>`app/models/spree/oauth_identity.rb` | Working | Client secrets encrypted at rest via Active Record Encryption (`encrypts`). |
| **Facebook Data Deletion Callback** | Official Meta data-deletion compliance callback with HMAC signature verification and deletion logging. | `app/controllers/spree/api/v3/store/facebook_data_deletions_controller.rb` | Working | Unlinks `OauthIdentity` without deleting customer account. |
| **Webhook & n8n Integration** | Spree outbound webhooks for event notification to external services (n8n, automation workflows). | `db/migrate/20260326203012_improve_spree_webhooks.spree.rb` | Working | Uses HMAC signature headers (`X-Spree-Webhook-Signature`). |

---

## 7. Media Storage, Email & Market Customizations

| Feature | Description | Key Files | Status | Notes or Risks |
| :--- | :--- | :--- | :--- | :--- |
| **Cloudflare R2 Storage** | Active Storage configured for S3-compatible Cloudflare R2 bucket storage. | `config/storage.yml`<br>`config/environments/production.rb` | Working | Pre-signed short-lived URLs used for secure attachment access. |
| **Transactional Email (Resend)** | SMTP mail delivery configured for Resend or generic SMTP services with Mailpit fallback in development. | `config/environments/production.rb` | Working | Delivery adapter configured via `SMTP_HOST` environment variables. |
| **Nepal Currency & Shipping Calculator** | Custom shipping rate calculator resolving fees by customer district with fallback to configurable default fee. | `app/models/spree/calculator/shipping/district_shipping.rb`<br>`app/models/spree/district.rb`<br>`app/controllers/spree/admin/district_fees_controller.rb` | Partial | Requires mass assignment fix (`SEC-01`) in `DistrictFeesController`. |

---
*Generated based on empirical analysis of arghamart backend codebase.*
