"use client";

import { useRouter } from "next/navigation";
import { useTranslations } from "next-intl";
import { useEffect, useRef, useState } from "react";
import { toast } from "sonner";
import { useAuth } from "@/contexts/AuthContext";
import {
  getOauthProviders,
  type OauthProviderInfo,
  oauthLogin,
} from "@/lib/data/oauth";

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
  const [providers, setProviders] = useState<OauthProviderInfo[] | null>(null);

  useEffect(() => {
    getOauthProviders().then(setProviders);
  }, []);

  const google = providers?.find((p) => p.provider === "google");
  if (!google) return null;

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
      <div className="mt-4">
        <GoogleSignInButton
          clientId={google.client_id}
          redirectUrl={redirectUrl}
        />
      </div>
    </div>
  );
}
