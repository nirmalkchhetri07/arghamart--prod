"use client";

import { Facebook, Github } from "lucide-react";
import { usePathname, useRouter } from "next/navigation";
import { useTranslations } from "next-intl";
import { useEffect, useRef, useState } from "react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { useAuth } from "@/contexts/AuthContext";
import {
  buildAuthorizeUrl,
  createOauthState,
  isOauthCodeProvider,
  type OauthCodeProvider,
  oauthStateKey,
} from "@/lib/auth/oauth-client";
import {
  getOauthProviders,
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

function GoogleSignInButton({
  clientId,
  redirectUrl,
}: {
  clientId: string;
  redirectUrl: string | null;
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
            if (result.success) {
              await refreshUser();
              if (redirectUrl) router.push(redirectUrl);
            } else {
              toast.error(t(`errors.${result.errorCode ?? "failed"}`));
            }
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
  }, [clientId, redirectUrl, refreshUser, router, t]);

  return <div ref={buttonRef} className="flex justify-center" />;
}

/**
 * Redirect-based sign-in for the authorization-code providers (Facebook,
 * GitHub). Starts the provider's OAuth dialog with this page's callback URL
 * as redirect_uri — the callback page completes the flow server-side.
 */
function CodeProviderButton({
  provider,
  clientId,
  basePath,
  redirectUrl,
}: {
  provider: OauthCodeProvider;
  clientId: string;
  basePath: string;
  redirectUrl: string | null;
}) {
  const t = useTranslations("oauth");
  const Icon = provider === "facebook" ? Facebook : Github;

  function start() {
    const redirectUri = `${window.location.origin}${basePath}/auth/callback/${provider}`;
    const { state, nonce } = createOauthState(redirectUrl);
    try {
      sessionStorage.setItem(oauthStateKey(provider), nonce);
    } catch {
      // Private browsing without storage: the callback still rejects a
      // mismatched state, failing closed rather than signing in blindly.
    }
    window.location.href = buildAuthorizeUrl(provider, {
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
      <Icon className="h-5 w-5" aria-hidden />
      {provider === "facebook"
        ? t("continueWithFacebook")
        : t("continueWithGitHub")}
    </Button>
  );
}

/**
 * Social sign-in buttons for the login and register pages. Renders one
 * button per enabled, implemented provider from the Store API — unknown
 * providers render nothing, and the whole block renders nothing when no
 * providers are enabled.
 */
export function SocialLoginButtons({
  redirectUrl,
}: {
  redirectUrl: string | null;
}) {
  const t = useTranslations("oauth");
  const pathname = usePathname();
  const basePath = extractBasePath(pathname ?? "");
  const [providers, setProviders] = useState<OauthProviderInfo[] | null>(null);

  useEffect(() => {
    getOauthProviders().then(setProviders);
  }, []);

  const google = providers?.find((p) => p.provider === "google");
  const codeProviders = (providers ?? []).filter((p) =>
    isOauthCodeProvider(p.provider),
  );
  if (!google && codeProviders.length === 0) return null;

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
          />
        )}
        {codeProviders.map((p) => (
          <CodeProviderButton
            key={p.provider}
            provider={p.provider as OauthCodeProvider}
            clientId={p.client_id}
            basePath={basePath}
            redirectUrl={redirectUrl}
          />
        ))}
      </div>
    </div>
  );
}
