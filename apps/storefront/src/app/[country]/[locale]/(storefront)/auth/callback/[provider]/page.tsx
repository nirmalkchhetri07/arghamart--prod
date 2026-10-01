"use client";

import Link from "next/link";
import {
  useParams,
  usePathname,
  useRouter,
  useSearchParams,
} from "next/navigation";
import { useTranslations } from "next-intl";
import { Suspense, useEffect, useRef, useState } from "react";
import { useAuth } from "@/contexts/AuthContext";
import {
  isOauthCodeProvider,
  oauthStateKey,
  parseOauthState,
} from "@/lib/auth/oauth-client";
import { oauthLogin } from "@/lib/data/oauth";
import { resolveAccountRedirect } from "@/lib/utils/account-redirect";
import { extractBasePath } from "@/lib/utils/path";

/**
 * OAuth callback for the redirect-based providers (Facebook, GitHub).
 *
 * The provider redirects here with `?code=&state=`. We verify the state
 * nonce against sessionStorage, then exchange the code through the Store API
 * (the client secret never leaves the backend) and land on the original
 * return target. Register one URL per market, e.g.
 * `https://shop.example/us/en/auth/callback/facebook`, in each provider app.
 */
function OauthCallbackInner() {
  const params = useParams<{ provider: string }>();
  const searchParams = useSearchParams();
  const pathname = usePathname();
  const router = useRouter();
  const basePath = extractBasePath(pathname ?? "");
  const t = useTranslations("oauth");
  const { refreshUser } = useAuth();
  const startedRef = useRef(false);
  const [errorCode, setErrorCode] = useState<string | null>(null);

  useEffect(() => {
    if (startedRef.current) return;
    startedRef.current = true;

    async function complete() {
      const provider = params.provider ?? "";
      if (!isOauthCodeProvider(provider)) {
        setErrorCode("failed");
        return;
      }
      if (searchParams.get("error")) {
        setErrorCode("cancelled");
        return;
      }
      const code = searchParams.get("code");
      const parsed = parseOauthState(searchParams.get("state"));
      let stored: string | null = null;
      try {
        stored = sessionStorage.getItem(oauthStateKey(provider));
        sessionStorage.removeItem(oauthStateKey(provider));
      } catch {
        stored = null;
      }
      if (!code || !parsed || !stored || parsed.nonce !== stored) {
        setErrorCode("failed");
        return;
      }
      const next = resolveAccountRedirect(parsed.next, basePath);
      const redirectUri = `${window.location.origin}${pathname}`;
      const result = await oauthLogin(provider, code, redirectUri);
      if (result.success) {
        await refreshUser();
        router.replace(next ?? `${basePath}/account`);
      } else {
        setErrorCode(result.errorCode ?? "failed");
      }
    }

    void complete();
  }, [basePath, params.provider, pathname, refreshUser, router, searchParams]);

  if (errorCode) {
    return (
      <div className="max-w-md mx-auto px-4 sm:px-6 lg:px-8 py-16 text-center">
        <h1 className="text-xl font-semibold text-gray-900">
          {t(`errors.${errorCode}`)}
        </h1>
        <p className="mt-4">
          <Link
            href={`${basePath}/account`}
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

export default function OauthCallbackPage() {
  return (
    <Suspense>
      <OauthCallbackInner />
    </Suspense>
  );
}
