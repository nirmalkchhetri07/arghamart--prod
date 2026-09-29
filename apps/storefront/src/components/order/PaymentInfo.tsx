import type { CreditCard, Payment, StoreCredit } from "@spree/sdk";
import { useTranslations } from "next-intl";
import { PaymentIcon } from "react-svg-credit-card-payment-icons";
import { ManualQrReuploadForm } from "@/components/order/ManualQrReuploadForm";
import { getCardIconType, getCardLabel } from "@/lib/utils/credit-card";

interface PaymentInfoProps {
  payment: Payment;
  /** Label override for store credit payments (e.g. "Gift Card") */
  storeCreditLabel?: string;
  /** Absolute proof-image URL, resolved server-side (API host is server-only) */
  proofImageUrl?: string | null;
  /** Order id, required to offer a re-upload after a rejection */
  orderId?: string;
}

/** Extra Manual QR fields the backend serializer adds (absent from SDK types). */
interface ManualQrPayment extends Payment {
  qr_status?: string | null;
  qr_transaction_id?: string | null;
  qr_rejection_reason?: string | null;
}

function isManualQrPayment(payment: Payment): payment is ManualQrPayment {
  const type = payment.payment_method?.type ?? "";
  return (
    type === "manual_qr" ||
    type === "Spree::PaymentMethod::ManualQr" ||
    type.toLowerCase().includes("manual_qr")
  );
}

export function PaymentInfo({
  payment,
  storeCreditLabel,
  proofImageUrl,
  orderId,
}: PaymentInfoProps) {
  const t = useTranslations("orders");
  const source = payment.source;

  if (isManualQrPayment(payment)) {
    const status = payment.qr_status ?? "pending";
    const statusLabel =
      status === "verified"
        ? t("manualQrStatusVerified")
        : status === "rejected"
          ? t("manualQrStatusRejected")
          : t("manualQrStatusPending");
    return (
      <div>
        <p className="text-sm font-medium text-gray-900">
          {payment.payment_method?.name}
        </p>
        <p className="text-xs text-gray-500">{payment.display_amount}</p>
        <p className="mt-1 inline-block rounded-full bg-gray-100 px-2 py-0.5 text-xs font-medium text-gray-700">
          {statusLabel}
        </p>
        {payment.qr_transaction_id && (
          <p className="mt-1 text-xs text-gray-500">
            {t("manualQrTransactionId")}: {payment.qr_transaction_id}
          </p>
        )}
        {proofImageUrl && (
          // biome-ignore lint/performance/noImgElement: proof resolves through an authorized redirect to the file host.
          <img
            src={proofImageUrl}
            alt={t("manualQrProof")}
            className="mt-2 max-w-[280px] rounded border"
          />
        )}
        {status === "rejected" && (
          <div className="mt-1">
            {payment.qr_rejection_reason && (
              <p className="text-xs text-red-600">
                {t("manualQrRejectionReason")}: {payment.qr_rejection_reason}
              </p>
            )}
            {orderId && <ManualQrReuploadForm orderId={orderId} />}
          </div>
        )}
      </div>
    );
  }

  if (payment.source_type === "credit_card" && source) {
    const card = source as CreditCard;
    return (
      <div className="flex items-center gap-3">
        <PaymentIcon
          type={getCardIconType(card.brand)}
          format="flatRounded"
          width={40}
        />
        <div>
          <p className="text-sm font-medium text-gray-900">
            {t("cardEndingIn", {
              label: getCardLabel(card.brand),
              digits: card.last4,
            })}
          </p>
          <p className="text-xs text-gray-500">
            {t("cardExpires", {
              month: String(card.month).padStart(2, "0"),
              year: card.year,
            })}
          </p>
        </div>
      </div>
    );
  }

  if (payment.source_type === "store_credit" && source) {
    const credit = source as StoreCredit;
    const label = storeCreditLabel || t("storeCredit");
    return (
      <div>
        <p className="text-sm font-medium text-gray-900">{label}</p>
        <p className="text-xs text-gray-500">
          {t("storeCreditApplied", {
            amount: payment.display_amount ?? "",
            remaining: credit.display_amount_remaining,
          })}
        </p>
      </div>
    );
  }

  return (
    <div>
      <p className="text-sm font-medium text-gray-900">
        {payment.payment_method?.name}
      </p>
      <p className="text-xs text-gray-500">{payment.display_amount}</p>
    </div>
  );
}
