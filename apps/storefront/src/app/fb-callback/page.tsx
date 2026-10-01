"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useTranslations } from "next-intl";
import { useEffect, useRef, useState } from "react";
import {
  OauthPendingForm,
  type PendingOAuthState,
} from "@/components/auth/OauthPendingForm";
import {
  isPendingOauthCode,
  oauthReturnToKey,
  oauthStateKey,
  parseOauthState,
} from "@/lib/auth/oauth-client";
import { oauthLogin } from "@/lib/data/oauth";
import { resolveAccountRedirect } from "@/lib/utils/account-redirect";
import { extractBasePath } from "@/lib/utils/path";

function readCookie(name: string): string | null {
  const entry = document.cookie
    .split("; ")
    .find((cookie) => cookie.startsWith(`${name}=`));
  return entry ? decodeURIComponent(entry.slice(name.length + 1)) : null;
}

/**
 * Country/locale base path for fallbacks: market cookies first (where the
 * customer started the flow), then the configured defaults. Read only after
 * mount so server and client render the same markup.
 */
function defaultBasePath(): string {
  const country =
    readCookie("spree_country") ||
    process.env.NEXT_PUBLIC_DEFAULT_COUNTRY ||
    "us";
  const locale =
    readCookie("spree_locale") ||
    process.env.NEXT_PUBLIC_DEFAULT_LOCALE ||
    "en";
  return `/${country}/${locale}`;
}

/**
 * Validate a stored return target: a local path that resolves to that
 * market's account/checkout (the same rule every login redirect obeys).
 * `state` was nonce-checked against sessionStorage before this runs, so the
 * value is the one this browser stored when the flow started.
 */
function safeNext(target: string | null | undefined): string | null {
  if (!target) return null;
  return resolveAccountRedirect(target, extractBasePath(target));
}

/**
 * Facebook's fixed redirect target (locale-independent on purpose — Meta
 * matches `redirect_uri` exactly). The dialog returns the result in the URL
 * fragment (`#access_token=…&state=…`); we validate the state nonce against
 * sessionStorage, exchange the token through the Store API, and land on the
 * stored return target (or the default account page for the current market).
 */
function FbCallbackInner() {
  const t = useTranslations("oauth");
  const router = useRouter();
  const startedRef = useRef(false);
  const [basePath, setBasePath] = useState<string | null>(null);
  const [nextPath, setNextPath] = useState<string | null>(null);
  const [errorCode, setErrorCode] = useState<string | null>(null);
  const [pending, setPending] = useState<PendingOAuthState | null>(null);

  useEffect(() => {
    if (startedRef.current) return;
    startedRef.current = true;

    const marketBasePath = defaultBasePath();
    setBasePath(marketBasePath);

    const query = new URLSearchParams(window.location.search);
    const hash = window.location.hash.replace(/^#/, "");
    const fragment = new URLSearchParams(hash);
    const param = (key: string) => fragment.get(key) ?? query.get(key);

    const providerError = param("error");
    const accessToken = param("access_token");
    const rawState = param("state");

    if (providerError) {
      setErrorCode(providerError === "access_denied" ? "cancelled" : "failed");
      return;
    }

    const parsed = parseOauthState(rawState);
    let storedNonce: string | null = null;
    let storedReturnTo: string | null = null;
    try {
      storedNonce = sessionStorage.getItem(oauthStateKey("facebook"));
      sessionStorage.removeItem(oauthStateKey("facebook"));
      storedReturnTo = sessionStorage.getItem(oauthReturnToKey("facebook"));
      sessionStorage.removeItem(oauthReturnToKey("facebook"));
    } catch {
      // Storage unavailable: the checks below fail closed.
    }

    if (
      !accessToken ||
      !parsed ||
      !storedNonce ||
      parsed.nonce !== storedNonce
    ) {
      setErrorCode("failed");
      return;
    }

    const target = safeNext(parsed.next) ?? safeNext(storedReturnTo);
    setNextPath(target);

    void (async () => {
      const result = await oauthLogin("facebook", accessToken);
      if (result.success) {
        router.replace(target ?? `${marketBasePath}/account`);
        return;
      }
      const errorCode = result.errorCode;
      if (result.pendingOAuth && errorCode && isPendingOauthCode(errorCode)) {
        setPending({ code: errorCode, pendingOAuth: result.pendingOAuth });
        return;
      }
      setErrorCode(errorCode ?? "failed");
    })();
  }, [router]);

  if (pending) {
    const destination = nextPath ?? `${basePath ?? ""}/account`;
    return (
      <div className="max-w-md mx-auto px-4 sm:px-6 lg:px-8 py-16">
        <OauthPendingForm
          state={pending}
          onAuthed={() => router.replace(destination)}
          onCancel={() => router.push(`${basePath ?? ""}/account`)}
        />
      </div>
    );
  }

  if (errorCode) {
    return (
      <div className="max-w-md mx-auto px-4 sm:px-6 lg:px-8 py-16 text-center">
        <h1 className="text-xl font-semibold text-gray-900">
          {t(`errors.${errorCode}`)}
        </h1>
        <p className="mt-4">
          <Link
            href={`${basePath ?? ""}/account`}
            className="text-sm text-primary hover:text-primary/70 font-medium"
          >
            {t("backToSignIn")}
          </Link>
        </p>
      </div>
    );
  }

  return (
    <div className="max-w-md mx-auto px-4 sm:px-6 lg:px-8 py-16 text-center">
      <p className="text-sm text-gray-500">{t("completingSignIn")}</p>
    </div>
  );
}

export default function FbCallbackPage() {
  return <FbCallbackInner />;
}
