import { render, screen } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";
import type { FulfillmentWithDelivery } from "@/components/order/delivery";
import { FulfillmentBlock } from "@/components/order/FulfillmentBlock";

vi.mock("next-intl", () => ({
  NextIntlClientProvider: ({ children }: { children: React.ReactNode }) =>
    children,
  useTranslations: () => (key: string) => {
    const messages: Record<string, string> = {
      delivered: "Delivered",
      deliveryAddress: "Delivery Address",
      shippingMethod: "Shipping Method",
      canceled: "Canceled",
      trackItems: "Track Items",
      ncmStatus: "NCM Status",
    };
    return messages[key] ?? key;
  },
}));

function fulfillment(overrides: Partial<FulfillmentWithDelivery> = {}) {
  return {
    id: "ful_1",
    number: "H1",
    tracking: null,
    tracking_url: null,
    status: "shipped",
    fulfillment_type: "shipping",
    fulfilled_at: null,
    items: [],
    delivery_method: { name: "Standard" },
    stock_location: { name: "Warehouse" },
    delivery_rates: [],
    ...overrides,
  } as unknown as FulfillmentWithDelivery;
}

function renderBlock(f: FulfillmentWithDelivery) {
  return render(
    <FulfillmentBlock
      fulfillment={f}
      shipAddress={null}
      basePath="/np/en"
      lineItems={[]}
    />,
  );
}

describe("FulfillmentBlock delivery badge", () => {
  it("shows only Delivered (not Shipped) when the fulfillment is delivered", () => {
    renderBlock(
      fulfillment({ delivered: true, delivered_at: "2026-09-15T19:06:41Z" }),
    );

    expect(screen.getByText("Delivered")).toBeInTheDocument();
    expect(screen.queryByText("shipped")).not.toBeInTheDocument();
  });

  it("shows only Shipped while undelivered", () => {
    renderBlock(fulfillment({ delivered: false, delivered_at: null }));

    expect(screen.getByText("shipped")).toBeInTheDocument();
    expect(screen.queryByText("Delivered")).not.toBeInTheDocument();
  });

  it("falls back to the raw status for other states", () => {
    renderBlock(
      fulfillment({ status: "pending", delivered: false, delivered_at: null }),
    );

    expect(screen.getByText("pending")).toBeInTheDocument();
    expect(screen.queryByText("Delivered")).not.toBeInTheDocument();
  });

  it("shows NCM courier status and tracking metadata when present", () => {
    renderBlock(
      fulfillment({
        ncm_status: "Pickup Order Created",
        ncm_tracking_id: "NCM-12345",
        ncm_cod_amount: "1200.00",
      }),
    );

    expect(screen.getByText("NCM:")).toBeInTheDocument();
    expect(screen.getByText("Pickup Order Created")).toBeInTheDocument();
    expect(screen.getByText("NCM-12345")).toBeInTheDocument();
    expect(document.body).toHaveTextContent(/COD:\s*NPR\s*1,200\.00/);
  });
});
