/**
 * Facebook Login JS SDK helpers (https://connect.facebook.net/en_US/sdk.js).
 *
 * Sign-in runs popup-first via `FB.login`, which hands back a user access
 * token the storefront posts to the Store API. Two situations cannot use a
 * popup — an in-app browser (the Facebook/Instagram webview) and a blocked
 * popup window — and both fall back to the full-page dialog redirect that
 * lands on the locale-independent `/fb-callback` page.
 *
 * The SDK domain must be listed in the Meta app's "Allowed Domains for the
 * JavaScript SDK"; the `/fb-callback` URL must be in "Valid OAuth Redirect
 * URIs". When the SDK is unavailable for any reason the popup path reports
 * "unavailable" and the caller redirects instead — the redirect flow needs
 * no SDK at all.
 */

import {
  buildFacebookAuthorizeUrl,
  FB_CALLBACK_PATH,
} from "@/lib/auth/oauth-client";

export const FACEBOOK_SDK_SRC = "https://connect.facebook.net/en_US/sdk.js";
export const FACEBOOK_SDK_VERSION = "v20.0";

interface FacebookAuthResponse {
  accessToken: string;
}

export interface FacebookLoginResponse {
  authResponse?: FacebookAuthResponse | null;
  status?: string;
}

export interface FacebookSdk {
  init(options: {
    appId: string;
    version: string;
    cookie?: boolean;
    xfbml?: boolean;
  }): void;
  login(
    callback: (response: FacebookLoginResponse) => void,
    options?: Record<string, unknown>,
  ): void;
}

declare global {
  interface Window {
    FB?: FacebookSdk;
    fbAsyncInit?: () => void;
  }
}

/** A popup sign-in result: an access token, an explicit cancellation, or
 * "unavailable" when no popup could run (SDK load failure / blocked popup). */
export type FacebookLoginOutcome =
  | { token: string }
  | "cancelled"
  | "unavailable";

let sdkPromise: Promise<FacebookSdk> | null = null;
let initializedAppId: string | null = null;

function initSdk(sdk: FacebookSdk, appId: string): FacebookSdk {
  sdk.init({
    appId,
    version: FACEBOOK_SDK_VERSION,
    cookie: false,
    xfbml: false,
  });
  initializedAppId = appId;
  return sdk;
}

/**
 * Load the Facebook SDK once and init it with the admin-configured app id.
 * Rejects when the script cannot load (domain not allow-listed, offline) so
 * callers can fall back to the redirect flow.
 */
export function loadFacebookSdk(appId: string): Promise<FacebookSdk> {
  if (typeof window === "undefined") {
    return Promise.reject(new Error("no window"));
  }
  if (window.FB) {
    // Same app: already live. Different app (admin rotated the id): re-init.
    return Promise.resolve(
      initializedAppId === appId ? window.FB : initSdk(window.FB, appId),
    );
  }
  if (!sdkPromise) {
    sdkPromise = new Promise<FacebookSdk>((resolve, reject) => {
      const previousAsyncInit = window.fbAsyncInit;
      window.fbAsyncInit = () => {
        previousAsyncInit?.();
        if (!window.FB) {
          reject(new Error("facebook sdk missing"));
          return;
        }
        resolve(initSdk(window.FB, appId));
      };
      // A stale element from a failed load never fires fbAsyncInit again —
      // drop it so the re-append actually re-executes the script.
      document.getElementById("facebook-jssdk")?.remove();
      const script = document.createElement("script");
      script.id = "facebook-jssdk";
      script.src = FACEBOOK_SDK_SRC;
      script.async = true;
      script.defer = true;
      script.onerror = () => {
        sdkPromise = null;
        reject(new Error("facebook sdk load failed"));
      };
      document.head.appendChild(script);
    });
  }
  return sdkPromise;
}

/** Facebook/Instagram in-app browsers: popups do not work reliably there. */
export function isFacebookInAppBrowser(
  userAgent: string | undefined = typeof navigator === "undefined"
    ? undefined
    : navigator.userAgent,
): boolean {
  if (!userAgent) return false;
  return /FBAN|FBAV|Instagram/i.test(userAgent);
}

/** The exact `redirect_uri` the Facebook dialog returns to. */
export function facebookRedirectUri(origin: string): string {
  return `${origin}${FB_CALLBACK_PATH}`;
}

/** Full-page dialog URL used when a popup is impossible (in-app browser,
 * blocked popup, or an SDK that will not load). */
export function facebookAuthorizeUrl({
  appId,
  origin,
  state,
}: {
  appId: string;
  origin: string;
  state: string;
}): string {
  return buildFacebookAuthorizeUrl({
    clientId: appId,
    redirectUri: facebookRedirectUri(origin),
    state,
  });
}

/**
 * Probe whether a popup window can still be opened right now: the probe runs
 * inside the click's user-activation window, exactly like the FB.login popup
 * itself would, so a blocked probe predicts a blocked login. Any thrown or
 * missing window counts as "cannot open".
 */
function canOpenPopup(): boolean {
  try {
    const probe = window.open(
      "about:blank",
      "facebook_login_probe",
      "width=1,height=1",
    );
    if (!probe) return false;
    probe.close();
    return true;
  } catch {
    return false;
  }
}

/**
 * Run `FB.login` in a popup and resolve with the user access token.
 * Resolves "cancelled" when the customer dismisses the dialog and
 * "unavailable" when no popup can run — callers then fall back to the
 * `/fb-callback` redirect flow.
 */
export async function facebookPopupLogin(
  appId: string,
): Promise<FacebookLoginOutcome> {
  if (typeof window === "undefined") return "unavailable";

  let sdk: FacebookSdk;
  try {
    sdk = await loadFacebookSdk(appId);
  } catch {
    return "unavailable";
  }
  if (!canOpenPopup()) return "unavailable";

  return new Promise<FacebookLoginOutcome>((resolve) => {
    let settled = false;
    const settle = (outcome: FacebookLoginOutcome) => {
      if (!settled) {
        settled = true;
        resolve(outcome);
      }
    };
    try {
      sdk.login(
        (response) => {
          const token = response?.authResponse?.accessToken;
          if (token) settle({ token });
          else settle("cancelled");
        },
        { scope: "public_profile,email", response_type: "token" },
      );
    } catch {
      settle("unavailable");
    }
  });
}
