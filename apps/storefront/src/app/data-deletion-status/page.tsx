"use client";

import Link from "next/link";
import { useSearchParams } from "next/navigation";
import { useTranslations } from "next-intl";
import { Suspense } from "react";

/**
 * Public status page for Facebook's data-deletion callback: the backend
 * responds to Meta with `{ url: "/data-deletion-status?code=…" }` and this
 * page shows the customer their confirmation code. Locale comes from the
 * market cookies via the layout, not the URL.
 */
function DataDeletionStatusInner() {
  const t = useTranslations("dataDeletion");
  const searchParams = useSearchParams();
  const code = searchParams.get("code");

  return (
    <main className="max-w-md mx-auto px-4 sm:px-6 lg:px-8 py-16 text-center">
      <h1 className="text-xl font-semibold text-gray-900">{t("title")}</h1>
      <p className="mt-4 text-sm text-gray-600">
        {code ? t("received") : t("codeMissing")}
      </p>
      {code && (
        <p className="mt-4 text-sm text-gray-600">
          <span className="font-medium text-gray-900">{t("codeLabel")}:</span>{" "}
          <code className="mt-1 inline-block rounded bg-gray-100 px-2 py-1 font-mono text-sm text-gray-900">
            {code}
          </code>
        </p>
      )}
      <p className="mt-4 text-sm text-gray-600">{t("note")}</p>
      <p className="mt-6">
        <Link
          href="/"
          className="text-sm text-primary hover:text-primary/70 font-medium"
        >
          {t("backToStore")}
        </Link>
      </p>
    </main>
  );
}

export default function DataDeletionStatusPage() {
  return (
    <Suspense fallback={null}>
      <DataDeletionStatusInner />
    </Suspense>
  );
}
