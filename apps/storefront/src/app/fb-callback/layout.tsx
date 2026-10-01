import type { Metadata } from "next";
import { cookies } from "next/headers";
import { NextIntlClientProvider } from "next-intl";
import { Suspense } from "react";
import "../globals.css";
import { DocumentShell } from "@/components/layout/DocumentShell";
import {
  DEFAULT_LOCALE,
  loadMessages,
  resolveSupportedLocale,
} from "@/i18n/locales";

/**
 * Locale-independent shell for the Facebook callback: the dialog redirects
 * here without any /{country}/{locale} prefix (Facebook matches the
 * redirect_uri exactly), so this segment loads messages from the market
 * cookies instead of the URL.
 */
export const metadata: Metadata = {
  title: "Facebook sign-in",
  robots: { index: false, follow: false },
};

async function LocalizedFbCallbackShell({
  children,
}: {
  children: React.ReactNode;
}) {
  const cookieStore = await cookies();
  const locale =
    resolveSupportedLocale(cookieStore.get("spree_locale")?.value) ??
    DEFAULT_LOCALE;
  const messages = await loadMessages(locale);

  return (
    <DocumentShell locale={locale}>
      <NextIntlClientProvider locale={locale} messages={messages}>
        {children}
      </NextIntlClientProvider>
    </DocumentShell>
  );
}

export default function FbCallbackLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <Suspense
      fallback={
        <DocumentShell locale={DEFAULT_LOCALE}>
          <NextIntlClientProvider locale={DEFAULT_LOCALE}>
            {children}
          </NextIntlClientProvider>
        </DocumentShell>
      }
    >
      <LocalizedFbCallbackShell>{children}</LocalizedFbCallbackShell>
    </Suspense>
  );
}
