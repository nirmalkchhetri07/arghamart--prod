# Forward-Looking Recommendations & Development Roadmap: arghamart

**Project:** arghamart  
**Audit Date:** October 2, 2026  
**Auditor:** Antigravity AI Code Audit Engine  

---

## 1. Recommended New Features & Improvements

| Feature / Improvement | Why It Matters | Expected Benefit | Effort (S/M/L) | Priority (P1/P2/P3) | Dependencies |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **OCR Automatic Proof Verification** | Manual QR proof review is labor-intensive and prone to human delay. | Automatically extract transaction ID & amount from uploaded screenshots using Tesseract/Vision API, pre-verifying 80% of proofs. | **M** | **P2** | Manual QR module |
| **SMS Gateway Integration (Sparrow SMS / Aakash SMS)** | Phone numbers are the primary identifier in Nepal; email open rates are low. | Send order updates, delivery notifications, and password reset codes via local SMS gateways. | **M** | **P1** | `Spree::User#phone` field |
| **Storefront Order Tracking Page** | Guest customers currently rely on support to track delivery state. | Allow customers to check order status and delivery tracking using order number + phone number. | **S** | **P2** | Store API |
| **Meilisearch Full-Text Search Activation** | Database ILIKE search performance degrades as product catalog grows. | Typo-tolerant, instant search results with instant faceted filtering for storefront. | **S** | **P3** | Meilisearch container in `docker-compose.prod.yml` |

---

## 2. Refactors & Technical Debt to Address

### Refactor 1: Sanitize District Fee Bulk Update Parameters
- **Current Approach:** `DistrictFeesController#bulk_update` relies on `permit!.to_h`.
- **Suggested Approach:** Map parameters through an explicit permitted parameters filter or loop through integer/prefix keys, ensuring string inputs are validated as numeric decimals before calling `update`.

### Refactor 2: Add Case-Insensitive Database Indexes for Geography
- **Current Approach:** `AddressDecorator#province_name=` and `#district_name=` execute `where('LOWER(name) = ?', ...)`, forcing full table scans.
- **Suggested Approach:** Add expression indexes on `LOWER(name)` for `spree_provinces` and `spree_districts` in a Rails migration:
  ```ruby
  add_index :spree_provinces, "LOWER(name)", name: "index_spree_provinces_on_lower_name"
  add_index :spree_districts, "LOWER(name)", name: "index_spree_districts_on_lower_name"
  ```

### Refactor 3: Consolidated Devise Route Declarations
- **Current Approach:** Devise routes are defined both inside `Spree::Core::Engine.add_routes` and at the top level of `config/routes.rb`.
- **Suggested Approach:** Keep Devise routes exclusively within the Spree core engine block to eliminate duplicate named route helpers and route parsing overhead.

---

## 3. Scalability, Monitoring, Backup & CI/CD Recommendations

1. **Automated PostgreSQL Backup Pipeline**:
   - Set up daily `pg_dump` cron jobs backed up to an isolated Cloudflare R2 bucket or AWS S3 bucket with 30-day retention policies.
   - Script location recommendation: `scripts/backup_db.sh`.
2. **Sentry Exception & Performance Monitoring**:
   - Activate Sentry performance tracing in `config/initializers/sentry.rb` to capture payment gateway latency and external HTTP call durations (eSewa/Khalti API endpoints).
3. **Continuous Integration (GitHub Actions)**:
   - Configure a GitHub Actions pipeline (`.github/workflows/ci.yml`) running `brakeman`, `bundle audit`, `rubocop`, and `rspec` inside Docker containers on every pull request.

---

## 4. Suggested 30 / 60 / 90-Day Roadmap

```
+-------------------------------------------------------------------------------+
| DAY 1 - 30: SECURITY HARDENING & PRODUCTION STABILITY                         |
|  - Fix Mass Assignment in DistrictFeesController                              |
|  - Implement Rate Limiting on Proof Upload Endpoints                          |
|  - Enforce strict environment variables for Mission Control Jobs in Prod       |
|  - Add pessimistic locking (with_lock) on Manual QR proof uploads             |
+-------------------------------------------------------------------------------+
                                      |
                                      v
+-------------------------------------------------------------------------------+
| DAY 31 - 60: DATA INTEGRITY & INTEGRATION EXTENSIONS                          |
|  - Add PostgreSQL lower(name) expression indexes for geography search         |
|  - Integrate local Nepal SMS Gateway (Sparrow/Aakash SMS) for order updates   |
|  - Set up automated daily database dumps to Cloudflare R2                     |
|  - Establish GitHub Actions CI pipeline for automated security scanning       |
+-------------------------------------------------------------------------------+
                                      |
                                      v
+-------------------------------------------------------------------------------+
| DAY 61 - 90: PERFORMANCE OPTIMIZATION & ADVANCED FEATURES                     |
|  - Enable Meilisearch container and reindex product catalog                   |
|  - Implement OCR assisted payment proof verification for admin desk           |
|  - Configure Redis / Solid Cache memory tuning for high-traffic sales         |
+-------------------------------------------------------------------------------+
```

---

## 5. Future AI Assistance (Ready-to-Use Implementation Prompts)

### Prompt 1: Fix Mass Assignment in DistrictFeesController
```text
Task: Fix mass assignment vulnerability in DistrictFeesController.
Context: File app/controllers/spree/admin/district_fees_controller.rb line 55 uses `params.fetch(:fees, {}).permit!.to_h`.
Constraints: Do not break bulk fee update form behavior in /admin/manage-fee.
Acceptance Criteria:
1. Remove `permit!` call.
2. Filter params.fetch(:fees, {}) so only numeric values keyed by integer string IDs or "dist_" prefixed IDs are permitted.
3. Add a controller spec in spec/requests/spree/admin/nepal_fees_spec.rb verifying unpermitted parameters are ignored.
```

### Prompt 2: Implement Rate Limiting on Manual QR Upload Controllers
```text
Task: Add rate limiting to storefront Manual QR proof upload endpoints.
Context: Controllers `Spree::Api::V3::Store::ManualQrProofsController` and `Spree::Api::V3::Store::Carts::ManualQrProofsController`.
Constraints: Must use Rails built-in rate_limit or Rack::Attack without breaking guest checkout flows.
Acceptance Criteria:
1. Limit proof upload attempts to 5 requests per minute per IP address.
2. Return HTTP 429 Too Many Requests with standard Spree API error format when limit exceeded.
3. Include request spec verifying rate limit enforcement.
```

### Prompt 3: Add Expression Indexes for Nepal Geography
```text
Task: Create Rails migration for case-insensitive indexes on Nepal geography tables.
Context: Models Spree::Province and Spree::District queried via LOWER(name).
Constraints: PostgreSQL compatible migration.
Acceptance Criteria:
1. Generate migration `db/migrate/add_lower_name_indexes_to_nepal_geography.rb`.
2. Add index on `spree_provinces` and `spree_districts` using `LOWER(name)`.
3. Verify migration runs cleanly with `bin/rails db:migrate` and `db:rollback`.
```

---
*Generated for arghamart development planning.*
