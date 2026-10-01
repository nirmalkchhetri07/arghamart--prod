"use client";

import { Github } from "lucide-react";
import { usePathname, useRouter } from "next/navigation";
import { useTranslations } from "next-intl";
import { useCallback, useEffect, useRef, useState } from "react";
import { toast } from "sonner";
import {
  OauthPendingForm,
  type PendingOAuthState,
} from "@/components/auth/OauthPendingForm";
import { Button } from "@/components/ui/button";
import { useAuth } from "@/contexts/AuthContext";
import {
  facebookPopupLogin,
  facebookRedirectUri,
  isFacebookInAppBrowser,
  loadFacebookSdk,
} from "@/lib/auth/facebook";
import {
  buildFacebookAuthorizeUrl,
  buildGithubAuthorizeUrl,
  createOauthState,
  isOauthCodeProvider,
  isPendingOauthCode,
  oauthReturnToKey,
  oauthStateKey,
} from "@/lib/auth/oauth-client";
import {
  getOauthProviders,
  type OauthLoginResult,
  type OauthProviderInfo,
  oauthLogin,
} from "@/lib/data/oauth";
import { extractBasePath } from "@/lib/utils/path";

declare global {
  interface Window {
    google?: {
      accounts: {
        id: {
          initialize(options: {
            client_id: string;
            callback: (response: { credential: string }) => void;
          }): void;
          renderButton(
            element: HTMLElement,
            options?: Record<string, unknown>,
          ): void;
        };
      };
    };
  }
}

const GSI_SRC = "https://accounts.google.com/gsi/client";

let gsiPromise: Promise<void> | null = null;

function loadGsi(): Promise<void> {
  if (typeof window === "undefined")
    return Promise.reject(new Error("no window"));
  if (window.google?.accounts?.id) return Promise.resolve();
  if (!gsiPromise) {
    gsiPromise = new Promise<void>((resolve, reject) => {
      const script = document.createElement("script");
      script.src = GSI_SRC;
      script.async = true;
      script.defer = true;
      script.onload = () => resolve();
      script.onerror = () => {
        gsiPromise = null;
        reject(new Error("gsi load failed"));
      };
      document.head.appendChild(script);
    });
  }
  return gsiPromise;
}

/**
 * Shared handling for a finished (or still pending) social sign-in:
 * success runs the caller's navigation, the two pending codes swap the
 * button block for the inline completion form, everything else toasts a
 * localized error.
 */
function useLoginResultHandler(
  onPending: (pending: PendingOAuthState) => void,
): (
  result: OauthLoginResult,
  onSuccess: () => void | Promise<void>,
) => Promise<void> {
  const t = useTranslations("oauth");
  return useCallback(
    async (result: OauthLoginResult, onSuccess: () => void | Promise<void>) => {
      if (result.success) {
        await onSuccess();
        return;
      }
      const errorCode = result.errorCode;
      if (result.pendingOAuth && errorCode && isPendingOauthCode(errorCode)) {
        onPending({ code: errorCode, pendingOAuth: result.pendingOAuth });
        return;
      }
      toast.error(t(`errors.${errorCode ?? "failed"}`));
    },
    [onPending, t],
  );
}

function GoogleSignInButton({
  clientId,
  redirectUrl,
  onResult,
}: {
  clientId: string;
  redirectUrl: string | null;
  onResult: ReturnType<typeof useLoginResultHandler>;
}) {
  const t = useTranslations("oauth");
  const router = useRouter();
  const { refreshUser } = useAuth();
  const buttonRef = useRef<HTMLDivElement>(null);
  const toastedRef = useRef(false);

  useEffect(() => {
    let cancelled = false;
    loadGsi()
      .then(() => {
        if (cancelled || !buttonRef.current || !window.google) return;
        window.google.accounts.id.initialize({
          client_id: clientId,
          callback: async (response) => {
            const result = await oauthLogin("google", response.credential);
            await onResult(result, async () => {
              await refreshUser();
              if (redirectUrl) router.push(redirectUrl);
            });
          },
        });
        window.google.accounts.id.renderButton(buttonRef.current, {
          theme: "outline",
          size: "large",
          width: 320,
        });
      })
      .catch(() => {
        if (!cancelled && !toastedRef.current) {
          toastedRef.current = true;
          toast.error(t("errors.loadFailed"));
        }
      });
    return () => {
      cancelled = true;
    };
  }, [clientId, onResult, redirectUrl, refreshUser, router, t]);

  return <div ref={buttonRef} className="flex justify-center" />;
}

/**
 * Facebook sign-in via the JS SDK. Prefers a popup (`FB.login`); falls back
 * to the full-page dialog redirect landing on `/fb-callback` when a popup is
 * impossible — inside the Facebook/Instagram in-app browser, when the popup
 * is blocked, or when the SDK fails to load. State nonce + return target go
 * into sessionStorage before either path leaves the page.
 */
function FacebookLoginButton({
  appId,
  basePath,
  redirectUrl,
  onResult,
}: {
  appId: string;
  basePath: string;
  redirectUrl: string | null;
  onResult: ReturnType<typeof useLoginResultHandler>;
}) {
  const t = useTranslations("oauth");
  const router = useRouter();
  const { refreshUser } = useAuth();
  const [busy, setBusy] = useState(false);

  // Preload the SDK on render so the popup opens inside the click's
  // user-activation window (popups opened after an await are blocked).
  useEffect(() => {
    loadFacebookSdk(appId).catch(() => {
      // Redirect flow needs no SDK — start() falls back to it.
    });
  }, [appId]);

  function start() {
    if (busy) return;
    setBusy(true);
    void (async () => {
      try {
        const { state, nonce } = createOauthState(redirectUrl);
        try {
          sessionStorage.setItem(oauthStateKey("facebook"), nonce);
          sessionStorage.setItem(
            oauthReturnToKey("facebook"),
            redirectUrl ?? "",
          );
        } catch {
          // Private browsing without storage: the /fb-callback page rejects
          // a missing or mismatched state, failing closed.
        }
        const origin = window.location.origin;
        const dialogUrl = () =>
          buildFacebookAuthorizeUrl({
            clientId: appId,
            redirectUri: facebookRedirectUri(origin),
            state,
          });

        if (isFacebookInAppBrowser()) {
          // In-app browser (FBAN/FBAV/Instagram): popups don't work — go
          // through the dialog page, which returns to /fb-callback.
          window.location.href = dialogUrl();
          return;
        }

        const outcome = await facebookPopupLogin(appId);
        if (outcome === "unavailable") {
          // Blocked popup or SDK failed to load: same dialog redirect — it
          // needs no SDK, so sign-in still works.
          window.location.href = dialogUrl();
          return;
        }
        if (outcome === "cancelled") {
          toast.error(t("errors.cancelled"));
          return;
        }

        const result = await oauthLogin("facebook", outcome.token);
        await onResult(result, async () => {
          await refreshUser();
          router.push(redirectUrl || `${basePath}/account`);
        });
      } finally {
        setBusy(false);
      }
    })();
  }

  return (
    <div className="flex justify-center">
      <Button
        type="button"
        variant="outline"
        size="lg"
        className="relative h-10 w-[320px] px-3"
        onClick={start}
      >
        <span className="absolute left-3 inline-flex">
          <FacebookBrandIcon />
        </span>
        {t("continueWithFacebook")}
      </Button>
    </div>
  );
}

function FacebookBrandIcon() {
  return (
    <svg
      aria-hidden="true"
      className="h-5 w-5"
      viewBox="0 0 24 24"
      fill="none"
    >
      <circle cx="12" cy="12" r="10" fill="#1877F2" />
      <path
        fill="#fff"
        d="M13.4 20v-7h2.35l.35-2.73H13.4V8.53c0-.79.22-1.33 1.36-1.33h1.45V4.76c-.25-.03-1.1-.1-2.09-.1-2.07 0-3.49 1.26-3.49 3.58v2.03H8.28V13h2.35v7h2.77Z"
      />
    </svg>
  );
}

/**
 * GitHub redirects through the localized callback page, which exchanges the
 * authorization code server-side (client secret never leaves the backend).
 */
function GithubButton({
  clientId,
  basePath,
  redirectUrl,
}: {
  clientId: string;
  basePath: string;
  redirectUrl: string | null;
}) {
  const t = useTranslations("oauth");

  function start() {
    const redirectUri = `${window.location.origin}${basePath}/auth/callback/github`;
    const { state, nonce } = createOauthState(redirectUrl);
    try {
      sessionStorage.setItem(oauthStateKey("github"), nonce);
    } catch {
      // Private browsing without storage: the callback still rejects a
      // mismatched state, failing closed rather than signing in blindly.
    }
    window.location.href = buildGithubAuthorizeUrl({
      clientId,
      redirectUri,
      state,
    });
  }

  return (
    <Button
      type="button"
      variant="outline"
      size="lg"
      className="w-full"
      onClick={start}
    >
      <Github className="h-5 w-5" aria-hidden />
      {t("continueWithGitHub")}
    </Button>
  );
}

/**
 * Social sign-in buttons for the login and register pages. Renders one
 * button per enabled, implemented provider from the Store API — unknown
 * providers render nothing, and the whole block renders nothing when no
 * providers are enabled. When the backend answers with one of the two
 * pending codes, the buttons are swapped for the inline completion form.
 */
export function SocialLoginButtons({
  redirectUrl,
}: {
  redirectUrl: string | null;
}) {
  const t = useTranslations("oauth");
  const pathname = usePathname();
  const router = useRouter();
  const basePath = extractBasePath(pathname ?? "");
  const { refreshUser } = useAuth();
  const [providers, setProviders] = useState<OauthProviderInfo[] | null>(null);
  const [pending, setPending] = useState<PendingOAuthState | null>(null);

  useEffect(() => {
    getOauthProviders().then(setProviders);
  }, []);

  const handleResult = useLoginResultHandler(setPending);

  const finishSocial = async () => {
    await refreshUser();
    router.push(redirectUrl || `${basePath}/account`);
  };

  const google = providers?.find((p) => p.provider === "google");
  const facebook = providers?.find((p) => p.provider === "facebook");
  const github = (providers ?? []).find((p) => isOauthCodeProvider(p.provider));

  if (!google && !facebook && !github) return null;

  if (pending) {
    return (
      <div className="mt-4">
        <OauthPendingForm
          state={pending}
          onAuthed={finishSocial}
          onCancel={() => setPending(null)}
        />
      </div>
    );
  }

  return (
    <div className="mt-4">
      <div className="relative">
        <div className="absolute inset-0 flex items-center">
          <div className="w-full border-t border-gray-200" />
        </div>
        <div className="relative flex justify-center text-sm">
          <span className="px-2 bg-white text-gray-500">
            {t("orContinueWith")}
          </span>
        </div>
      </div>
      <div className="mt-4 flex flex-col gap-2">
        {google && (
          <GoogleSignInButton
            clientId={google.client_id}
            redirectUrl={redirectUrl}
            onResult={handleResult}
          />
        )}
        {facebook && (
          <FacebookLoginButton
            appId={facebook.client_id}
            basePath={basePath}
            redirectUrl={redirectUrl}
            onResult={handleResult}
          />
        )}
        {github && (
          <GithubButton
            clientId={github.client_id}
            basePath={basePath}
            redirectUrl={redirectUrl}
          />
        )}
      </div>
    </div>
  );
}
