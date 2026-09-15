# Spree Commerce Application

## Using the project skill
/home/nirmalkchhetri/Desktop/arghamart/.agents/skills
/home/nirmalkchhetri/Desktop/arghamart/.claude/skills

## Project Structure

| Directory | Description |
|-----------|-------------|
| `backend/` | Rails API application (Spree Commerce) |
| `apps/storefront/` | Next.js storefront |

## Agent Instructions

- **Backend work** (Ruby/Rails, Spree models, API, database): See `backend/CLAUDE.md`
- **Storefront work** (Next.js, React, TypeScript): See `apps/storefront/CLAUDE.md`

## Spree Documentation

Full developer docs are installed locally:

```
node_modules/@spree/docs/dist/
├── developer/
│   ├── core-concepts/     # Products, orders, payments, inventory, etc.
│   ├── customization/     # Decorators, extensions, configuration, dependencies
│   ├── admin/             # Admin panel customization
│   ├── storefront/        # Storefront building guides
│   ├── sdk/               # TypeScript SDK documentation
│   └── tutorial/          # Step-by-step tutorials
├── api-reference/
│   ├── store-api/         # Store API v3 guides
│   ├── admin-api/         # Admin API v3 guides
│   └── store.yaml         # OpenAPI 3.0 spec (all endpoints, params, schemas)
└── integrations/          # Stripe, Meilisearch, etc.
```

Read these files when you need Spree-specific guidance.

## Querying the Admin API

Project setup mints a read-only secret key into `.spree/credentials.json`
(gitignored) — and `spree api` mints it on first use if setup was skipped —
so the Admin API client works without further configuration. Use it to
inspect live data instead of guessing at the schema:

```bash
pnpm spree api get products                      # list products
pnpm spree api get "orders?q[state_eq]=complete" # Ransack filters
pnpm spree api endpoints                         # every endpoint + its required scope
pnpm spree api schema "POST /products"           # request/response schema for an operation
```

The default key is read-only. For writes, create a scoped key and pass it via
`SPREE_API_KEY`: `pnpm spree api-key create --scopes write_products`, then
`SPREE_API_KEY=sk_... pnpm spree api post products --data '{"name":"New product","prices":[{"currency":"USD","amount":"29.99"}]}'`.

## Common Commands

```bash
pnpm run dev              # Start the Spree API (Docker)
pnpm run stop             # Stop services
pnpm run console          # Rails console
pnpm run logs             # Backend logs
pnpm spree api get products  # Query the Admin API (read-only key preconfigured)
pnpm spree eject          # Build the API locally from backend/
```
