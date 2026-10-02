"use server";

import { getConfig } from "@/lib/spree";
import { finalizeAuth } from "./customer";

export interface OauthProviderInfo {
  provider: string;
  name: string;
  client_id: string;
}

export type OauthErrorCode =
  | "invalid_token"
  | "provider_disabled"
  | "email_not_verified"
  | "email_missing"
  | "account_exists_confirm_required"
  | "invalid_credentials"
  | "failed";

/**
 * Outcome of a social sign-in. On `email_missing` /
 * `account_exists_confirm_required` the backend issues a short-lived,
 * single-use `pendingOAuth` token: the inline form finishes the flow via
 * `completeOauthLogin` instead of failing the sign-in.
 */
export interface OauthLoginResult {
  success: boolean;
  user?: {
    id: string;
    email: string;
    first_name?: string | null;
    last_name?: string | null;
  };
  errorCode?: OauthErrorCode;
  pendingOAuth?: string;
}

const KNOWN_ERROR_CODES: readonly OauthErrorCode[] = [
  "invalid_token",
  "provider_disabled",
  "email_not_verified",
  "email_missing",
  "account_exists_confirm_required",
  "invalid_credentials",
];

function apiBase(): { baseUrl: string; publishableKey: string } {
  const config = getConfig();
  return {
    baseUrl: config.baseUrl.replace(/\/$/, ""),
    publishableKey: config.publishableKey,
  };
}

/**
 * Enabled social-login providers for the sign-in UI. Returns [] when none
 * are configured (buttons render nothing) or the backend is unreachable.
 */
export async function getOauthProviders(): Promise<OauthProviderInfo[]> {
  try {
    const { baseUrl, publishableKey } = apiBase();
    const response = await fetch(`${baseUrl}/api/v3/store/oauth_providers`, {
      headers: { "x-spree-api-key": publishableKey },
      next: { revalidate: 300, tags: ["oauth-providers"] },
    });
    if (!response.ok) return [];
    const body = await readJsonResponse<{ data?: OauthProviderInfo[] }>(
      response,
    );
    return Array.isArray(body.data) ? body.data : [];
  } catch {
    return [];
  }
}

interface AuthResponseBody {
  token?: string;
  refresh_token?: string;
  user?: {
    id: string;
    email: string;
    first_name?: string | null;
    last_name?: string | null;
  };
  error?: { code?: string };
  pending_oauth?: string;
}

async function toResult(
  response: Response,
  body: AuthResponseBody | null,
): Promise<OauthLoginResult> {
  if (response.ok && body?.token && body.refresh_token && body.user) {
    await finalizeAuth(body.token, body.refresh_token);
    return { success: true, user: body.user };
  }
  const code = body?.error?.code as OauthErrorCode | undefined;
  return {
    success: false,
    errorCode: code && KNOWN_ERROR_CODES.includes(code) ? code : "failed",
    pendingOAuth: body?.pending_oauth,
  };
}

async function postJson(path: string, payload: unknown): Promise<Response> {
  const { baseUrl, publishableKey } = apiBase();
  return fetch(`${baseUrl}${path}`, {
    method: "POST",
    headers: {
      "x-spree-api-key": publishableKey,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(payload),
  });
}

async function readJsonResponse<T = AuthResponseBody>(
  response: Response,
): Promise<T> {
  const contentType = response.headers.get("content-type") ?? "";
  if (!contentType.toLowerCase().includes("application/json")) {
    throw new Error(
      `OAuth request failed with HTTP ${response.status}: expected a JSON response`,
    );
  }
  return (await response.json()) as T;
}

/**
 * Sign in with a verified OAuth credential: a Google ID token, a Facebook
 * user access token (JS SDK popup or /fb-callback redirect), or a GitHub
 * authorization `code` with the exact `redirectUri` the storefront used at
 * the provider (required for the server-side exchange). Stores tokens and
 * merges the guest cart exactly like password login (via finalizeAuth).
 * Returns a stable error code for localized toasts, plus `pendingOAuth`
 * when the backend asks for an email or a password confirmation first.
 */
export async function oauthLogin(
  provider: string,
  credential: string,
  redirectUri?: string,
): Promise<OauthLoginResult> {
  try {
    const response = await postJson(
      `/api/v3/store/auth/${encodeURIComponent(provider)}`,
      redirectUri ? { credential, redirect_uri: redirectUri } : { credential },
    );
    const body = await readJsonResponse(response);
    return await toResult(response, body);
  } catch {
    return { success: false, errorCode: "failed" };
  }
}

/**
 * Finish a pending social sign-in started by `oauthLogin`:
 * - `email_missing` → supply `{ email }`: the account + identity are created
 *   (or the flow rotates to password confirmation if the email is taken).
 * - `account_exists_confirm_required` → supply `{ password }`: proves
 *   ownership of the existing account, links the identity, returns tokens.
 * Pending tokens are single-use and expire after 10 minutes.
 */
export async function completeOauthLogin(params: {
  pendingOAuth: string;
  email?: string;
  password?: string;
}): Promise<OauthLoginResult> {
  try {
    const { pendingOAuth, email, password } = params;
    const response = await postJson("/api/v3/store/auth/complete", {
      pending_oauth: pendingOAuth,
      ...(email !== undefined ? { email } : {}),
      ...(password !== undefined ? { password } : {}),
    });
    const body = await readJsonResponse(response);
    return await toResult(response, body);
  } catch {
    return { success: false, errorCode: "failed" };
  }
}
