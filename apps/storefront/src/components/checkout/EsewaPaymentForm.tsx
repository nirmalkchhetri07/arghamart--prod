"use client";

import { CircleAlert, Loader2, Wallet } from "lucide-react";
import { useTranslations } from "next-intl";
import { useCallback, useEffect, useRef, useState } from "react";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { createCheckoutPaymentSession } from "@/lib/data/payment";
import { saveRedirectSession } from "@/lib/utils/redirect-payment-session";

export interface EsewaPaymentFormHandle {
  confirmPayment: (returnUrl: string) => Promise<{ error?: string }>;
  fetchUpdates: () => Promise<void>;
}

interface EsewaPaymentFormProps {
  cartId: string;
  paymentMethodId: string;
  onReady: (handle: EsewaPaymentFormHandle) => void;
}

/**
 * POSTs the signed eSewa form fields via a real form navigation.
 * eSewa expects a browser form POST — never a fetch/XHR.
 */
function postToEsewa(formUrl: string, fields: Record<string, unknown>): void {
  const form = document.createElement("form");
  form.method = "POST";
  form.action = formUrl;
  form.style.display = "none";
  for (const [name, value] of Object.entries(fields)) {
    if (value == null) continue;
    const input = document.createElement("input");
    input.type = "hidden";
    input.name = name;
    input.value = String(value);
    form.appendChild(input);
  }
  document.body.appendChild(form);
  form.submit();
}

export function EsewaPaymentForm({
  cartId,
  paymentMethodId,
  onReady,
}: EsewaPaymentFormProps) {
  const t = useTranslations("checkout");
  const [error, setError] = useState<string | null>(null);
  const [redirecting, setRedirecting] = useState(false);

  // The session is created at submit time — after shipping is confirmed —
  // so the signed amount matches the final order total.
  const confirmPayment = useCallback(
    async (returnUrl: string): Promise<{ error?: string }> => {
      setError(null);
      setRedirecting(true);

      try {
        const result = await createCheckoutPaymentSession(
          cartId,
          paymentMethodId,
          { success_url: returnUrl, failure_url: returnUrl },
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
        const formUrl =
          (externalData.form_url as string | undefined) ??
          (externalData.payment_url as string | undefined);
        const formFields = externalData.form_fields as
          | Record<string, unknown>
          | undefined;

        if (!formUrl || !formFields || Object.keys(formFields).length === 0) {
          const msg = t("failedToInitPayment");
          setError(msg);
          setRedirecting(false);
          return { error: msg };
        }

        // Persist the session id before leaving — the gateway can't echo
        // `?session=` back, so the confirm page reads it from storage.
        saveRedirectSession(cartId, {
          sessionId: result.session.id,
          gateway: "esewa",
        });

        postToEsewa(formUrl, formFields);
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
        <span className="flex h-10 w-10 flex-shrink-0 items-center justify-center rounded-sm bg-green-50">
          <Wallet className="h-5 w-5 text-green-600" strokeWidth={1.5} />
        </span>
        <div>
          <p className="text-sm font-medium text-gray-900">
            {t("esewaRedirectTitle")}
          </p>
          <p className="mt-0.5 text-sm text-gray-500">
            {t("esewaRedirectInfo")}
          </p>
        </div>
      </div>

      {redirecting && (
        <p className="mt-3 flex items-center gap-2 text-sm text-gray-500">
          <Loader2 className="h-4 w-4 animate-spin" />
          {t("redirectingToGateway", { gateway: "eSewa" })}
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
