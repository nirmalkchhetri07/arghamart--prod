import type { Metadata } from "next";
import { cookies } from "next/headers";
import { NextIntlClientProvider } from "next-intl";
import "../globals.css";
import { DocumentShell } from "@/components/layout/DocumentShell";
import {
  DEFAULT_LOCALE,
  loadMessages,
  resolveSupportedLocale,
} from "@/i18n/locales";

/**
 * Locale-independent shell for the Facebook data-deletion status page:
 * linked from the { url } of the data-deletion callback response, so it
 * lives outside /{country}/{locale} like /fb-callback.
 */
export const metadata: Metadata = {
  title: "Data deletion status",
  robots: { index: false, follow: false },
};

export default async function DataDeletionStatusLayout({
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
