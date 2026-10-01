"use server";

import { getConfig } from "@/lib/spree";
import { finalizeAuth } from "./customer";

export interface OauthProviderInfo {
  provider: string;
  name: string;
  client_id: string;
}

type OauthErrorCode =
  | "invalid_token"
  | "provider_disabled"
  | "email_not_verified"
  | "failed";

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
    const body = (await response.json()) as { data?: OauthProviderInfo[] };
    return Array.isArray(body.data) ? body.data : [];
  } catch {
    return [];
  }
}

/**
 * Sign in with a verified OAuth credential: a Google ID token, or a
 * Facebook/GitHub authorization code (with the exact `redirectUri` the
 * storefront used at the provider, required for the server-side exchange).
 * Stores tokens and merges the guest cart exactly like password login
 * (via finalizeAuth). Returns a stable error code for localized toasts.
 */
export async function oauthLogin(
  provider: string,
  credential: string,
  redirectUri?: string,
): Promise<{
  success: boolean;
  user?: {
    id: string;
    email: string;
    first_name?: string | null;
    last_name?: string | null;
  };
  errorCode?: OauthErrorCode;
}> {
  try {
    const { baseUrl, publishableKey } = apiBase();
    const response = await fetch(
      `${baseUrl}/api/v3/store/auth/${encodeURIComponent(provider)}`,
      {
        method: "POST",
        headers: {
          "x-spree-api-key": publishableKey,
          "Content-Type": "application/json",
        },
        body: JSON.stringify(
          redirectUri
            ? { credential, redirect_uri: redirectUri }
            : { credential },
        ),
      },
    );
    const body = (await response.json().catch(() => null)) as {
      token?: string;
      refresh_token?: string;
      user?: {
        id: string;
        email: string;
        first_name?: string | null;
        last_name?: string | null;
      };
      error?: { code?: string };
    } | null;
    if (!response.ok || !body?.token || !body?.refresh_token || !body?.user) {
      const code = body?.error?.code;
      return {
        success: false,
        errorCode:
          code === "invalid_token" ||
          code === "provider_disabled" ||
          code === "email_not_verified"
            ? code
            : "failed",
      };
    }
    await finalizeAuth(body.token, body.refresh_token);
    return { success: true, user: body.user };
  } catch {
    return { success: false, errorCode: "failed" };
  }
}
