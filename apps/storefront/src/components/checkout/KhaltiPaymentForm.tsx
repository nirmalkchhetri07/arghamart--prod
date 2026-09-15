"use client";

import { CircleAlert, Loader2, Wallet } from "lucide-react";
import { useTranslations } from "next-intl";
import { useCallback, useEffect, useRef, useState } from "react";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { createCheckoutPaymentSession } from "@/lib/data/payment";
import { saveRedirectSession } from "@/lib/utils/redirect-payment-session";

export interface KhaltiPaymentFormHandle {
  confirmPayment: (returnUrl: string) => Promise<{ error?: string }>;
  fetchUpdates: () => Promise<void>;
}

interface KhaltiPaymentFormProps {
  cartId: string;
  paymentMethodId: string;
  onReady: (handle: KhaltiPaymentFormHandle) => void;
}

export function KhaltiPaymentForm({
  cartId,
  paymentMethodId,
  onReady,
}: KhaltiPaymentFormProps) {
  const t = useTranslations("checkout");
  const [error, setError] = useState<string | null>(null);
  const [redirecting, setRedirecting] = useState(false);

  // The session is created at submit time — after shipping is confirmed —
  // so the initiated amount matches the final order total.
  const confirmPayment = useCallback(
    async (returnUrl: string): Promise<{ error?: string }> => {
      setError(null);
      setRedirecting(true);

      try {
        const result = await createCheckoutPaymentSession(
          cartId,
          paymentMethodId,
          {
            return_url: returnUrl,
            website_url: window.location.origin,
          },
        );

        if (!result.success || !result.session) {
          const msg =
            (!result.success && result.error) || t("failedToCreateSession");
          setError(msg);
          setRedirecting(false);
          return { error: msg };
        }

        const externalData = result.session.external_data as Record<
          string,
          unknown
        >;
        const paymentUrl = externalData.payment_url as string | undefined;

        if (!paymentUrl) {
          const msg = t("failedToInitPayment");
          setError(msg);
          setRedirecting(false);
          return { error: msg };
        }

        // Persist the session id before leaving — the gateway can't echo
        // `?session=` back, so the confirm page reads it from storage.
        saveRedirectSession(cartId, {
          sessionId: result.session.id,
          gateway: "khalti",
        });

        window.location.href = paymentUrl;
        return {};
      } catch (err) {
        const msg =
          err instanceof Error ? err.message : t("failedToCreateSession");
        setError(msg);
        setRedirecting(false);
        return { error: msg };
      }
    },
    [cartId, paymentMethodId, t],
  );

  const fetchUpdates = useCallback(async () => {}, []);

  // Stable refs so the registered handle never goes stale.
  const onReadyRef = useRef(onReady);
  onReadyRef.current = onReady;
  const confirmPaymentRef = useRef(confirmPayment);
  confirmPaymentRef.current = confirmPayment;
  const fetchUpdatesRef = useRef(fetchUpdates);
  fetchUpdatesRef.current = fetchUpdates;

  useEffect(() => {
    onReadyRef.current({
      confirmPayment: (...args) => confirmPaymentRef.current(...args),
      fetchUpdates: (...args) => fetchUpdatesRef.current(...args),
    });
  }, []);

  return (
    <div>
      <div className="flex items-start gap-3">
        <span className="flex h-10 w-10 flex-shrink-0 items-center justify-center rounded-sm bg-purple-50">
          <Wallet className="h-5 w-5 text-purple-600" strokeWidth={1.5} />
        </span>
        <div>
          <p className="text-sm font-medium text-gray-900">
            {t("khaltiRedirectTitle")}
          </p>
          <p className="mt-0.5 text-sm text-gray-500">
            {t("khaltiRedirectInfo")}
          </p>
        </div>
      </div>

      {redirecting && (
        <p className="mt-3 flex items-center gap-2 text-sm text-gray-500">
          <Loader2 className="h-4 w-4 animate-spin" />
          {t("redirectingToGateway", { gateway: "Khalti" })}
        </p>
      )}

      {error && (
        <Alert variant="destructive" className="mt-3">
          <CircleAlert />
          <AlertDescription>{error}</AlertDescription>
        </Alert>
      )}
    </div>
  );
}
