"use client";

import { Loader2, Upload } from "lucide-react";
import { useRouter } from "next/navigation";
import { useTranslations } from "next-intl";
import { useState } from "react";
import { reuploadManualQrProof } from "@/lib/data/payment";

const ACCEPTED_TYPES = ["image/png", "image/jpeg", "image/webp"];
const MAX_BYTES = 5 * 1024 * 1024;

interface ManualQrReuploadFormProps {
  orderId: string;
}

/**
 * Replacement screenshot upload on the customer order page, shown when the
 * previous proof was rejected. Creates a fresh pending payment — the
 * rejected one stays as history.
 */
export function ManualQrReuploadForm({ orderId }: ManualQrReuploadFormProps) {
  const t = useTranslations("orders");
  const tc = useTranslations("checkout");
  const router = useRouter();
  const [file, setFile] = useState<File | null>(null);
  const [transactionId, setTransactionId] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);

  function handleFileChange(event: React.ChangeEvent<HTMLInputElement>) {
    const chosen = event.target.files?.[0] ?? null;
    setError(null);
    if (!chosen) {
      setFile(null);
      return;
    }
    if (!ACCEPTED_TYPES.includes(chosen.type) || chosen.size > MAX_BYTES) {
      setFile(null);
      setError(tc("manualQrInvalidFile"));
      return;
    }
    setFile(chosen);
  }

  async function handleSubmit(event: React.FormEvent) {
    event.preventDefault();
    if (!file || submitting) return;
    setError(null);
    setSubmitting(true);
    const result = await reuploadManualQrProof(
      orderId,
      file,
      transactionId.trim() || undefined,
    );
    setSubmitting(false);
    if (!result.success) {
      setError(result.error);
      return;
    }
    setFile(null);
    setTransactionId("");
    router.refresh();
  }

  return (
    <form onSubmit={handleSubmit} className="mt-2">
      <label
        htmlFor={`manual-qr-reupload-${orderId}`}
        className="flex cursor-pointer items-center gap-2 rounded-sm border border-dashed px-3 py-2 text-sm text-gray-700 hover:bg-gray-50"
      >
        <Upload className="h-4 w-4 flex-shrink-0 text-gray-400" />
        <span className="truncate">
          {file ? file.name : t("manualQrReupload")}
        </span>
        <input
          id={`manual-qr-reupload-${orderId}`}
          type="file"
          accept="image/png,image/jpeg,image/webp"
          className="sr-only"
          onChange={handleFileChange}
        />
      </label>
      <input
        type="text"
        value={transactionId}
        onChange={(event) => setTransactionId(event.target.value)}
        placeholder={tc("manualQrTransactionPlaceholder")}
        className="mt-2 w-full rounded-sm border px-3 py-2 text-sm text-gray-900 placeholder:text-gray-400"
      />
      {error && <p className="mt-1 text-sm text-red-600">{error}</p>}
      <button
        type="submit"
        disabled={!file || submitting}
        className="mt-2 inline-flex items-center gap-2 rounded-sm bg-black px-4 py-2 text-sm font-medium text-white hover:bg-gray-900 disabled:cursor-not-allowed disabled:opacity-50"
      >
        {submitting && <Loader2 className="h-4 w-4 animate-spin" />}
        {t("manualQrReuploadSubmit")}
      </button>
    </form>
  );
}
