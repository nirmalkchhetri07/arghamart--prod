/**
 * Client-safe OAuth helpers for the authorization-code providers
 * (Facebook, GitHub). Server actions live in `@/lib/data/oauth`; everything
 * here runs in the browser: authorize-URL building and the `state` round-trip
 * that carries the post-login return target through the provider.
 */

export const OAUTH_CODE_PROVIDERS = ["facebook", "github"] as const;

export type OauthCodeProvider = (typeof OAUTH_CODE_PROVIDERS)[number];

export function isOauthCodeProvider(value: string): value is OauthCodeProvider {
  return (OAUTH_CODE_PROVIDERS as readonly string[]).includes(value);
}

const FACEBOOK_AUTHORIZE_URL = "https://www.facebook.com/v20.0/dialog/oauth";
const GITHUB_AUTHORIZE_URL = "https://github.com/login/oauth/authorize";

interface AuthorizeUrlParams {
  clientId: string;
  redirectUri: string;
  state: string;
}

export function buildFacebookAuthorizeUrl({
  clientId,
  redirectUri,
  state,
}: AuthorizeUrlParams): string {
  const params = new URLSearchParams({
    client_id: clientId,
    redirect_uri: redirectUri,
    response_type: "code",
    scope: "email,public_profile",
    state,
  });
  return `${FACEBOOK_AUTHORIZE_URL}?${params.toString()}`;
}

export function buildGithubAuthorizeUrl({
  clientId,
  redirectUri,
  state,
}: AuthorizeUrlParams): string {
  const params = new URLSearchParams({
    client_id: clientId,
    redirect_uri: redirectUri,
    scope: "user:email",
    state,
  });
  return `${GITHUB_AUTHORIZE_URL}?${params.toString()}`;
}

export function buildAuthorizeUrl(
  provider: OauthCodeProvider,
  params: AuthorizeUrlParams,
): string {
  return provider === "facebook"
    ? buildFacebookAuthorizeUrl(params)
    : buildGithubAuthorizeUrl(params);
}

/** sessionStorage key holding the one-time CSRF nonce for a provider flow. */
export function oauthStateKey(provider: string): string {
  return `oauth:state:${provider}`;
}

function base64UrlEncode(raw: string): string {
  return btoa(raw).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function base64UrlDecode(encoded: string): string {
  const padded =
    encoded.replace(/-/g, "+").replace(/_/g, "/") +
    "=".repeat((4 - (encoded.length % 4)) % 4);
  return atob(padded);
}

/**
 * Pack the post-login return target (`next`) with a random CSRF nonce into an
 * opaque `state` value. The nonce must be stored (see `oauthStateKey`) before
 * redirecting and compared on the callback.
 */
export function createOauthState(next: string | null): {
  state: string;
  nonce: string;
} {
  const bytes = new Uint8Array(16);
  crypto.getRandomValues(bytes);
  const nonce = Array.from(bytes, (b) => b.toString(16).padStart(2, "0")).join(
    "",
  );
  const state = base64UrlEncode(JSON.stringify({ next, nonce }));
  return { state, nonce };
}

/**
 * Unpack a callback `state` value. Returns null when malformed — the callback
 * page treats that as a failed sign-in rather than guessing a redirect.
 */
export function parseOauthState(value: string | null): {
  next: string | null;
  nonce: string;
} | null {
  if (!value) return null;
  try {
    const parsed: unknown = JSON.parse(base64UrlDecode(value));
    if (
      typeof parsed !== "object" ||
      parsed === null ||
      !("nonce" in parsed) ||
      typeof (parsed as { nonce: unknown }).nonce !== "string" ||
      !("next" in parsed) ||
      ((parsed as { next: unknown }).next !== null &&
        typeof (parsed as { next: unknown }).next !== "string")
    ) {
      return null;
    }
    const { next, nonce } = parsed as { next: string | null; nonce: string };
    return { next, nonce };
  } catch {
    return null;
  }
}
