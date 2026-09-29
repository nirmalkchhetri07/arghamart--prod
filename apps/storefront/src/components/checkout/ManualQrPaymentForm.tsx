"use client";

import { CircleAlert, Loader2, QrCode, Upload } from "lucide-react";
import { useTranslations } from "next-intl";
import { useCallback, useEffect, useRef, useState } from "react";
import { Alert, AlertDescription } from "@/components/ui/alert";
import {
  completeCheckoutPaymentSession,
  uploadManualQrProof,
} from "@/lib/data/payment";

export interface ManualQrPaymentFormHandle {
  confirmPayment: (returnUrl: string) => Promise<{ error?: string }>;
  fetchUpdates: () => Promise<void>;
  clearError: () => void;
}

interface ManualQrPaymentFormProps {
  cartId: string;
  sessionId: string;
  qrImageUrl?: string;
  instructions?: string;
  amountDue: string | null;
  currency: string;
  onReady: (handle: ManualQrPaymentFormHandle) => void;
}

const ACCEPTED_TYPES = ["image/png", "image/jpeg", "image/webp"];
const MAX_BYTES = 5 * 1024 * 1024;

/**
 * Manual QR checkout form. The payment session (QR image URL + instructions)
 * is pre-created by PaymentSection on method select — like Stripe, not like
 * the redirect gateways — and the amount stays in sync through the standard
 * session-update flow. At Pay time the screenshot is uploaded and the session
 * completed inline, so the order completes in the same submit without leaving
 * the page. The payment stays `pending` until an admin approves the proof.
 */
export function ManualQrPaymentForm({
  cartId,
  sessionId,
  qrImageUrl,
  instructions,
  amountDue,
  currency,
  onReady,
}: ManualQrPaymentFormProps) {
  const t = useTranslations("checkout");
  const tc = useTranslations("common");
  const [error, setError] = useState<string | null>(null);
  const [file, setFile] = useState<File | null>(null);
  const [fileError, setFileError] = useState<string | null>(null);
  const [transactionId, setTransactionId] = useState("");
  const [submitting, setSubmitting] = useState(false);

  // Refs so the registered handle never goes stale across session updates.
  const sessionRef = useRef(sessionId);
  sessionRef.current = sessionId;
  const fileRef = useRef<File | null>(null);
  fileRef.current = file;
  const transactionRef = useRef("");
  transactionRef.current = transactionId;

  const confirmPayment = useCallback(
    async (_returnUrl: string): Promise<{
      error?: string;
    }> => {
    setError(null);
    setFileError(null);

    const chosen = fileRef.current;
    if (!chosen) {
      const msg = t("manualQrNoFile");
      setFileError(msg);
      return { error: msg };
    }
    if (!ACCEPTED_TYPES.includes(chosen.type) || chosen.size > MAX_BYTES) {
      const msg = t("manualQrInvalidFile");
      setFileError(msg);
      return { error: msg };
    }

    setSubmitting(true);
    try {
      const activeSessionId = sessionRef.current;
      const uploaded = await uploadManualQrProof(
        cartId,
        activeSessionId,
        chosen,
      );
      if (!uploaded.success) {
        setError(uploaded.error);
        setSubmitting(false);
        return { error: uploaded.error };
      }

      const txn = transactionRef.current.trim();
      const completed = await completeCheckoutPaymentSession(
        cartId,
        activeSessionId,
        txn ? { external_data: { transaction_id: txn } } : undefined,
      );
      if (!completed.success) {
        setError(completed.error);
        setSubmitting(false);
        return { error: completed.error };
      }

      setSubmitting(false);
      return {};
    } catch (err) {
      const msg =
        err instanceof Error ? err.message : t("failedToCreateSession");
      setError(msg);
      setSubmitting(false);
      return { error: msg };
    }
  }, [cartId, t]);

  const fetchUpdates = useCallback(async () => {}, []);

  const clearError = useCallback(() => {
    setError(null);
    setFileError(null);
  }, []);

  const onReadyRef = useRef(onReady);
  onReadyRef.current = onReady;
  const confirmPaymentRef = useRef(confirmPayment);
  confirmPaymentRef.current = confirmPayment;
  const fetchUpdatesRef = useRef(fetchUpdates);
  fetchUpdatesRef.current = fetchUpdates;
  const clearErrorRef = useRef(clearError);
  clearErrorRef.current = clearError;

  useEffect(() => {
    onReadyRef.current({
      confirmPayment: (...args) => confirmPaymentRef.current(...args),
      fetchUpdates: (...args) => fetchUpdatesRef.current(...args),
      clearError: () => clearErrorRef.current(),
    });
  }, []);

  function handleFileChange(event: React.ChangeEvent<HTMLInputElement>) {
    const chosen = event.target.files?.[0] ?? null;
    setFileError(null);
    if (!chosen) {
      setFile(null);
      return;
    }
    if (!ACCEPTED_TYPES.includes(chosen.type) || chosen.size > MAX_BYTES) {
      setFile(null);
      setFileError(t("manualQrInvalidFile"));
      return;
    }
    setFile(chosen);
  }

  return (
    <div>
      <div className="flex items-start gap-3">
        <span className="flex h-10 w-10 flex-shrink-0 items-center justify-center rounded-sm bg-gray-100">
          <QrCode className="h-5 w-5 text-gray-700" strokeWidth={1.5} />
        </span>
        <div>
          <p className="text-sm font-medium text-gray-900">
            {t("manualQrTitle")}
          </p>
          <p className="mt-0.5 text-sm text-gray-500">{t("manualQrInfo")}</p>
        </div>
      </div>

      <div className="mt-3 rounded-sm border bg-gray-50 p-4">
        {qrImageUrl ? (
          // biome-ignore lint/performance/noImgElement: QR resolves through an Active Storage redirect to the file host.
          <img
            src={qrImageUrl}
            alt={t("manualQrTitle")}
            className="mx-auto max-w-[220px] rounded border bg-white"
          />
        ) : (
          <p className="text-sm text-gray-500">{t("manualQrNoQr")}</p>
        )}
        <p className="mt-2 text-center text-sm font-semibold text-gray-900">
          {t("manualQrAmountDue", {
            amount: amountDue ?? "",
            currency,
          })}
        </p>
        {instructions && (
          <p className="mt-1 text-center text-sm text-gray-600">
            {instructions}
          </p>
        )}
      </div>

      <div className="mt-3">
        <label
          htmlFor="manual-qr-proof"
          className="flex cursor-pointer items-center gap-2 rounded-sm border border-dashed px-4 py-3 text-sm text-gray-700 hover:bg-gray-50"
        >
          <Upload className="h-4 w-4 flex-shrink-0 text-gray-400" />
          <span className="truncate">
            {file ? file.name : t("manualQrUploadLabel")}
          </span>
          <input
            id="manual-qr-proof"
            type="file"
            accept="image/png,image/jpeg,image/webp"
            className="sr-only"
            onChange={handleFileChange}
          />
        </label>
        {fileError && <p className="mt-1 text-sm text-red-600">{fileError}</p>}
        <input
          type="text"
          value={transactionId}
          onChange={(event) => setTransactionId(event.target.value)}
          placeholder={t("manualQrTransactionPlaceholder")}
          className="mt-2 w-full rounded-sm border px-4 py-2.5 text-sm text-gray-900 placeholder:text-gray-400"
        />
      </div>

      {submitting && (
        <p className="mt-3 flex items-center gap-2 text-sm text-gray-500">
          <Loader2 className="h-4 w-4 animate-spin" />
          {tc("processing")}
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
