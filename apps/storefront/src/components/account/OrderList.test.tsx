import type { Order } from "@spree/sdk";
import { screen } from "@testing-library/react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, describe, expect, it, vi } from "vitest";
import { OrderList } from "@/components/account/OrderList";

vi.mock("next-intl/server", () => ({
  getTranslations: () => async (key: string) => {
    const messages: Record<string, string> = {
      order: "Order",
      date: "Date",
      payment: "Payment",
      shipment: "Shipment",
      totalColumn: "Total",
      actions: "Actions",
      view: "View",
      paid: "Paid",
      shipped: "Shipped",
      delivered: "Delivered",
      notAvailable: "N/A",
    };
    return messages[key] ?? key;
  },
}));

let root: Root | null = null;
let container: HTMLDivElement | null = null;

afterEach(() => {
  root?.unmount();
  root = null;
  container?.remove();
  container = null;
  document.body.innerHTML = "";
});

// NOTE: rendered via a raw React root (not RTL `render`): next/link defers
// its first commit past several macrotasks, and RTL's synchronous act-flush
// drops that yielded work, committing an empty tree. A real settle wait lets
// the genuine commit land.
async function renderList(orders: Order[]) {
  const ui = await OrderList({
    orders,
    basePath: "/np/en",
    locale: "en",
  });
  container = document.createElement("div");
  document.body.appendChild(container);
  root = createRoot(container);
  root.render(ui);
  await new Promise((resolve) => setTimeout(resolve, 500));
}

function order(overrides: Record<string, unknown> = {}) {
  return {
    id: "or_test1",
    number: "R000000001",
    completed_at: "2026-09-15T17:27:13Z",
    payment_status: "paid",
    fulfillment_status: "shipped",
    display_total: "$10.00",
    fulfillments: [],
    ...overrides,
  } as unknown as Order;
}

function deliveredFulfillment() {
  return {
    id: "ful_1",
    number: "H1",
    status: "shipped",
    delivered: true,
    delivered_at: "2026-09-15T19:06:41Z",
  };
}

describe("OrderList delivery badge", () => {
  it("shows Delivered (not Shipped) for delivered orders", async () => {
    await renderList([
      order({
        id: "or_VqXmZF31wY",
        number: "R672084530",
        fulfillments: [deliveredFulfillment()],
      }),
    ]);

    // findBy* (async) is required: next/link defers commit past RTL's sync flush
    const link = await screen.findByRole("link", { name: /R672084530/ });
    const tr = link.closest("tr");
    expect(tr).not.toBeNull();
    expect(tr?.textContent).toContain("Delivered");
    expect(tr?.textContent).not.toContain("Shipped");
  });

  it("shows Shipped while undelivered", async () => {
    await renderList([
      order({
        fulfillments: [
          { ...deliveredFulfillment(), delivered: false, delivered_at: null },
        ],
      }),
    ]);

    await screen.findByText("Shipped");
    expect(screen.queryByText("Delivered")).not.toBeInTheDocument();
  });
});
