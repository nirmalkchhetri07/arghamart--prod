"use client";

import { Loader2 } from "lucide-react";
import { usePathname, useRouter, useSearchParams } from "next/navigation";
import { useTranslations } from "next-intl";
import { use, useEffect, useRef } from "react";
import { confirmPaymentAndCompleteCart } from "@/lib/data/payment";
import { extractBasePath } from "@/lib/utils/path";
import {
  clearRedirectSession,
  readRedirectSession,
} from "@/lib/utils/redirect-payment-session";

interface ConfirmPaymentPageProps {
  params: Promise<{
    id: string;
    country: string;
    locale: string;
  }>;
}

/**
 * Intermediate page that offsite payment gateways redirect to.
 *
 * When a customer returns from an offsite gateway (e.g. Stripe 3D Secure,
 * Adyen Klarna/iDEAL, eSewa, Khalti), the payment webhook may not have
 * arrived yet. This page:
 * 1. Tries to complete the payment session (tells Spree to check with the provider)
 * 2. If successful, completes the order and redirects to order-placed
 * 3. If failed, redirects back to checkout with an error
 *
 * eSewa/Khalti return URLs are baked into the payment session before the
 * session id is known, so they can't echo `?session=` back. The session id
 * is read from local storage (saved before the redirect) instead, and the
 * gateway payload (`?data=` for eSewa, `?pidx=` for Khalti) is forwarded to
 * the backend, which verifies server-to-server.
 */
export default function ConfirmPaymentPage({
  params,
}: ConfirmPaymentPageProps) {
  const { id: cartId } = use(params);
  const t = useTranslations("checkout");
  const router = useRouter();
  const pathname = usePathname();
  const searchParams = useSearchParams();
  const basePath = extractBasePath(pathname);
  const attemptedRef = useRef(false);

  useEffect(() => {
    if (attemptedRef.current) return;
    attemptedRef.current = true;

    // Stripe: ?session={spreeSessionId}
    // Adyen:  ?sessionId={adyenSessionId}&redirectResult=...
    // eSewa:  ?data=<base64 payload> (success and failure URLs)
    // Khalti: ?pidx=... (plus transaction_id, status, ...)
    const sessionId = searchParams.get("session");
    const sessionResult = searchParams.get("sessionResult");
    const redirectResult = searchParams.get("redirectResult");
    const adyenSessionId = searchParams.get("sessionId");
    const esewaData = searchParams.get("data");
    const khaltiPidx = searchParams.get("pidx");

    // eSewa/Khalti can't echo the Spree session id — resolve it from the
    // ref saved before the offsite redirect.
    const storedRef = sessionId ? null : readRedirectSession(cartId);
    const resolvedSessionId = sessionId ?? storedRef?.sessionId;

    const externalData: Record<string, unknown> = {
      ...(esewaData ? { data: esewaData } : {}),
      ...(khaltiPidx ? { pidx: khaltiPidx } : {}),
    };

    async function confirmAndRedirect() {
      const result = await confirmPaymentAndCompleteCart(
        cartId,
        resolvedSessionId ?? undefined,
        sessionResult ?? undefined,
        redirectResult ?? undefined,
        adyenSessionId ?? undefined,
        Object.keys(externalData).length > 0 ? externalData : undefined,
      );

      clearRedirectSession(cartId);

      if (result.success) {
        // Cache the completed order for the thank-you page
        if (result.order) {
          const { cacheCompletedOrder } = await import(
            "@/lib/utils/completed-order-cache"
          );
          cacheCompletedOrder(cartId, result.order);
        }

        router.replace(`${basePath}/order-placed/${cartId}`);
      } else {
        const errorMessage = encodeURIComponent(
          result.error || t("paymentError"),
        );
        router.replace(
          `${basePath}/checkout/${cartId}?payment_error=${errorMessage}`,
        );
      }
    }

    confirmAndRedirect();
  }, [cartId, searchParams, basePath, router, t]);

  return (
    <div className="flex flex-col items-center justify-center py-20 gap-4">
      <Loader2 className="h-8 w-8 animate-spin text-gray-400" />
      <p className="text-sm text-gray-500">{t("confirmingPayment")}</p>
    </div>
  );
}
