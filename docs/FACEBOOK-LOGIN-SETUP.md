# Facebook Login — Meta app setup

How the Facebook sign-in for the storefront is wired and the exact values to
enter in the Meta app dashboard (developers.facebook.com → your app).

Flow: storefront **Facebook** button → FB JS SDK `FB.login` popup (fallback:
full-page dialog with `response_type=token` when the popup is blocked, the UA
is an in-app browser, or the SDK fails to load) → `/fb-callback` exchanges/validates
→ backend verifies the user access token server-side with the App Secret
(`debug_token` + `/me`, `appsecret_proof`). The App Secret never reaches the
browser; it lives encrypted in the admin-managed provider.

## 1. Create the app

1. <https://developers.facebook.com/apps> → **Create App** → Business (or
   Consumer) type.
2. Add the **Facebook Login** product.
3. Note the **App ID** and **App Secret** (Settings → Basic).

## 2. Exact dashboard values

Production storefront origin: `https://arghamart-prod.vercel.app`
(`NEXT_PUBLIC_SITE_URL`).

| Meta dashboard field | Value |
| --- | --- |
| App Domains (Settings → Basic) | `arghamart-prod.vercel.app` |
| Privacy Policy URL (Settings → Basic) | `https://arghamart-prod.vercel.app/us/en/policies/privacy-policy` |
| Data Deletion Request URL (Settings → Basic) | `https://arghamart-prod.vercel.app/api/facebook/data-deletion` |
| Website → Site URL (Settings → Basic) | `https://arghamart-prod.vercel.app` |
| Valid OAuth Redirect URIs (Facebook Login → Settings) | `https://arghamart-prod.vercel.app/fb-callback` |
| Allowed Domains for JavaScript SDK (Facebook Login → Settings) | `arghamart-prod.vercel.app` |

Local development (storefront on `http://localhost:3001`) — add alongside the
production values while testing:

| Meta dashboard field | Value |
| --- | --- |
| Valid OAuth Redirect URIs | `http://localhost:3001/fb-callback` |
| Allowed Domains for JavaScript SDK | `localhost` |

Rules:

- The redirect URI is exactly `${NEXT_PUBLIC_SITE_URL}/fb-callback` — **no**
  `[country]/[locale]` prefix. The page sits outside the locale router and is
  excluded in `src/lib/spree/middleware.ts` and `src/proxy.ts`, so the value
  must match character-for-character or `FB.login`/the dialog redirect fails
  with a redirect-URI mismatch.
- In Development mode the app is only usable by users added under App
  Roles → Testers/ Administrators; public use needs App Review for
  `public_profile` and `email`.

## 3. Admin → Settings → Social Login

Enter the credentials on the Facebook row (no env vars needed):

| Admin field | Meta field |
| --- | --- |
| **App ID** (`client_id`) | App ID |
| **App Secret** (`client_secret`, encrypted at rest, never rendered again) | App Secret |

Then toggle the provider **enabled**. The storefront picks it up from
`GET /api/v3/store/oauth_providers` (cached 5 minutes).

## 4. Data deletion callback

1. Meta POSTs a `signed_request` (form-encoded or JSON) to the **Data
   Deletion Request URL** (`/api/facebook/data-deletion`).
2. The Next route handler forwards it to the backend
   `POST /api/v3/store/facebook/data_deletion`, which verifies the HMAC-SHA256
   signature with the stored App Secret, removes only the matching
   `Spree::OauthIdentity` rows (the store account is kept), and logs a SHA-256
   hash of the Facebook user id for manual review.
3. The response is `{ url, confirmation_code }` per Meta's contract; `url`
   points at the public status page
   `https://arghamart-prod.vercel.app/data-deletion-status?code=<confirmation_code>`
   (relative `/data-deletion-status?code=…` if `STOREFRONT_URL`/
   `NEXT_PUBLIC_SITE_URL` are unset; the proxy absolutizes against the request
   origin). Confirmation codes are retained for 30 days.

Meta's own **Test** button (App Dashboard → Settings → Basic → Data Deletion
Request URL → Test) exercises this end to end.

## 5. CSP note

The storefront currently configures **no** Content-Security-Policy (no
`Content-Security-Policy` header, no `vercel.json`), so nothing needs to be
allowlisted for the SDK or Graph calls. If a CSP is added later, it must allow
`connect.facebook.net`, `www.facebook.com`, and `graph.facebook.com`
(`script-src`, `connect-src`, `frame-src` as applicable).

## 6. Manual verification checklist

- **(a) Popup happy path** — desktop browser, click Facebook on `/us/en/login`
  → FB popup → consent → popup closes → signed in, guest cart merged.
- **(b) In-app / blocked-popup fallback** — emulate an in-app UA (FBAN/FBAV/
  Instagram) or block popups → full-page Facebook dialog → returns to
  `/fb-callback` → signed in. Dismissing the popup only shows a toast.
- **(c) `email_missing`** — use an FB account without a confirmed email (or
  revoked email permission) → inline **email** form on `/fb-callback` →
  submitting completes the sign-in.
- **(d) `account_exists_confirm_required`** — use an FB account whose email
  matches an existing password account → inline **password** form → correct
  password links the identity; wrong password rejected; token is single-use
  and expires after 10 minutes.
- **(e) Data deletion** — Meta app dashboard → Data Deletion Request URL →
  **Test** → expect HTTP 200 `{ url, confirmation_code }`; open `url` → status
  page shows the code; backend log shows only the hashed Facebook user id.
- **(f) No locale redirect** — `GET /fb-callback` and `GET /data-deletion-status`
  return 200 at the site root (no `Location` to `/{country}/{locale}/…`);
  `GET /us/en/fb-callback` must 404. Middleware tests assert the same and
  production already behaves this way.
