/**
 * Maps raw Spree payment/shipment state strings to i18n translation keys
 * under the "orders" namespace.
 */

export const PAYMENT_STATE_KEY: Record<string, string> = {
  none: "none",
  authorized: "authorized",
  partially_paid: "partiallyPaid",
  paid: "paid",
  partially_refunded: "partiallyRefunded",
  refunded: "refunded",
  overcharged: "overcharged",
  voided: "voided",
};

export const SHIPMENT_STATE_KEY: Record<string, string> = {
  shipped: "shipped",
  partial: "partiallyShipped",
  delivered: "delivered",
  ready: "ready",
  pending: "pending",
  canceled: "canceled",
  backorder: "backorder",
};

export function getPaymentStatusColor(state: string | null): string {
  switch (state) {
    case "paid":
      return "bg-green-100 text-green-800";
    case "none":
    case "authorized":
    case "partially_paid":
    case "partially_refunded":
      return "bg-yellow-100 text-yellow-800";
    case "overcharged":
    case "voided":
      return "bg-red-100 text-red-800";
    default:
      return "bg-gray-100 text-gray-800";
  }
}

export function getShipmentStatusColor(state: string | null): string {
  switch (state) {
    case "shipped":
    case "delivered":
      return "bg-green-100 text-green-800";
    case "ready":
    case "pending":
    case "backorder":
      return "bg-yellow-100 text-yellow-800";
    case "partial":
      return "bg-blue-100 text-blue-800";
    case "canceled":
      return "bg-red-100 text-red-800";
    default:
      return "bg-gray-100 text-gray-800";
  }
}
