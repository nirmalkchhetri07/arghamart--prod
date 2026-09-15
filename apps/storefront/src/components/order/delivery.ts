import type { Fulfillment } from "@spree/sdk";

// The generated SDK Fulfillment type predates the backend's delivery tracking
// (see Spree::Api::V3::FulfillmentSerializerDecorator, which adds `delivered`
// / `delivered_at` to the Store API fulfillment payload). Extend locally so
// templates can read them without waiting on an SDK release.
export type FulfillmentWithDelivery = Fulfillment & {
  delivered?: boolean | null;
  delivered_at?: string | null;
};

export function isFulfillmentDelivered(
  fulfillment: Fulfillment | FulfillmentWithDelivery,
): boolean {
  return (fulfillment as FulfillmentWithDelivery).delivered === true;
}

// Order-level rule for list views (order history table): an order counts as
// delivered only when it has fulfillments and ALL of them are delivered — a
// partially delivered multi-shipment order must not claim "Delivered" in a
// single-badge row. Matches the admin order header semantics.
export function isOrderDelivered(
  fulfillments:
    | readonly (Fulfillment | FulfillmentWithDelivery)[]
    | null
    | undefined,
): boolean {
  if (!fulfillments || fulfillments.length === 0) return false;
  return fulfillments.every(isFulfillmentDelivered);
}
