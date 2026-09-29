import { act, render, screen } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";

vi.mock("next-intl", async () => {
  const actual = await vi.importActual("next-intl");
  return {
    ...actual,
    useTranslations: () => (key: string, values?: Record<string, string>) => {
      if (values?.gateway) return `${key}:${values.gateway}`;
      return key;
    },
  };
});

vi.mock("@/lib/data/payment", () => ({
  createCheckoutPaymentSession: vi.fn(),
  getRedirectCartAuth: vi.fn(),
}));

import type { PaymentSession } from "@spree/sdk";
import {
  createCheckoutPaymentSession,
  getRedirectCartAuth,
} from "@/lib/data/payment";
import {
  KhaltiPaymentForm,
  type KhaltiPaymentFormHandle,
} from "../KhaltiPaymentForm";

const mockCreate = vi.mocked(createCheckoutPaymentSession);
const mockAuth = vi.mocked(getRedirectCartAuth);

const khaltiSession = {
  id: "session-khalti",
  status: "pending",
  external_data: {
    pidx: "bZQLD9wRVWo4CdESSfuSsB",
    payment_url: "https://test-pay.khalti.com/?pidx=bZQLD9wRVWo4CdESSfuSsB",
  },
} as unknown as PaymentSession;

function renderForm(onReady: (handle: KhaltiPaymentFormHandle) => void) {
  return render(
    <KhaltiPaymentForm
      cartId="cart-1"
      paymentMethodId="pm-khalti"
      onReady={onReady}
    />,
  );
}

describe("KhaltiPaymentForm", () => {
  const realLocation = window.location;
  let href: string;

  beforeEach(() => {
    vi.clearAllMocks();
    window.sessionStorage.clear();
    window.localStorage.clear();
    mockAuth.mockResolvedValue({
      cartToken: "order-token-xyz",
      cartId: "cart-1",
      surface: "dtc" as const,
    });
    href = "";
    Object.defineProperty(window, "location", {
      value: {
        ...realLocation,
        origin: "https://shop.test",
        get href() {
          return href;
        },
        set href(value: string) {
          href = value;
        },
      },
      writable: true,
      configurable: true,
    });
  });

  it("renders redirect info and registers its handle", async () => {
    let handle: KhaltiPaymentFormHandle | null = null;

    await act(async () => {
      renderForm((h) => {
        handle = h;
      });
    });

    expect(screen.getByText("khaltiRedirectTitle")).toBeInTheDocument();
    expect(screen.getByText("khaltiRedirectInfo")).toBeInTheDocument();
    expect(handle).not.toBeNull();
  });

  it("creates a session and redirects to payment_url on confirm", async () => {
    mockCreate.mockResolvedValue({ success: true, session: khaltiSession });
    let handle: KhaltiPaymentFormHandle | null = null;

    await act(async () => {
      renderForm((h) => {
        handle = h;
      });
    });

    let outcome: { error?: string } | undefined;
    await act(async () => {
      outcome = await handle!.confirmPayment(
        "https://shop.test/us/en/confirm-payment/cart-1",
      );
    });

    expect(outcome).toEqual({});
    expect(mockCreate).toHaveBeenCalledWith("cart-1", "pm-khalti", {
      return_url: "https://shop.test/us/en/confirm-payment/cart-1",
      website_url: "https://shop.test",
    });
    expect(href).toBe(
      "https://test-pay.khalti.com/?pidx=bZQLD9wRVWo4CdESSfuSsB",
    );

    // Session id persisted for the confirm-payment return
    expect(window.sessionStorage.getItem("spree.redirect_session.cart-1")).toBe(
      JSON.stringify({
        sessionId: "session-khalti",
        gateway: "khalti",
        cartToken: "order-token-xyz",
      }),
    );

    // Redirecting state shown
    expect(screen.getByText("redirectingToGateway:Khalti")).toBeInTheDocument();
  });

  it("returns a user-facing error when session creation fails", async () => {
    mockCreate.mockResolvedValue({
      success: false,
      error: "Khalti is down",
    });
    let handle: KhaltiPaymentFormHandle | null = null;

    await act(async () => {
      renderForm((h) => {
        handle = h;
      });
    });

    let outcome: { error?: string } | undefined;
    await act(async () => {
      outcome = await handle!.confirmPayment("https://shop.test/return");
    });

    expect(outcome).toEqual({ error: "Khalti is down" });
    expect(href).toBe("");
    expect(
      window.sessionStorage.getItem("spree.redirect_session.cart-1"),
    ).toBeNull();
  });

  it("returns an error when the session has no payment_url", async () => {
    mockCreate.mockResolvedValue({
      success: true,
      session: { ...khaltiSession, external_data: {} },
    });
    let handle: KhaltiPaymentFormHandle | null = null;

    await act(async () => {
      renderForm((h) => {
        handle = h;
      });
    });

    let outcome: { error?: string } | undefined;
    await act(async () => {
      outcome = await handle!.confirmPayment("https://shop.test/return");
    });

    expect(outcome).toEqual({ error: "failedToInitPayment" });
    expect(href).toBe("");
  });
});
