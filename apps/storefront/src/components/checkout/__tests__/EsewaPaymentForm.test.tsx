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
}));

import type { PaymentSession } from "@spree/sdk";
import { createCheckoutPaymentSession } from "@/lib/data/payment";
import {
  EsewaPaymentForm,
  type EsewaPaymentFormHandle,
} from "../EsewaPaymentForm";

const mockCreate = vi.mocked(createCheckoutPaymentSession);

const esewaSession = {
  id: "session-esewa",
  status: "pending",
  external_data: {
    form_url: "https://rc-epay.esewa.com.np/api/epay/main/v2/form",
    form_fields: {
      amount: "100",
      tax_amount: "0",
      total_amount: "100",
      transaction_uuid: "txn-uuid-1",
      product_code: "EPAYTEST",
      product_service_charge: "0",
      product_delivery_charge: "0",
      success_url: "https://shop.test/us/en/confirm-payment/cart-1",
      failure_url: "https://shop.test/us/en/confirm-payment/cart-1",
      signed_field_names: "total_amount,transaction_uuid,product_code",
      signature: "c2lnbmF0dXJl",
    },
  },
} as unknown as PaymentSession;

function renderForm(onReady: (handle: EsewaPaymentFormHandle) => void) {
  return render(
    <EsewaPaymentForm
      cartId="cart-1"
      paymentMethodId="pm-esewa"
      onReady={onReady}
    />,
  );
}

describe("EsewaPaymentForm", () => {
  let submitSpy: ReturnType<typeof vi.spyOn>;

  beforeEach(() => {
    vi.clearAllMocks();
    window.sessionStorage.clear();
    window.localStorage.clear();
    document.body.innerHTML = "";
    submitSpy = vi
      .spyOn(HTMLFormElement.prototype, "submit")
      .mockImplementation(() => {});
  });

  it("renders redirect info and registers its handle", async () => {
    let handle: EsewaPaymentFormHandle | null = null;

    await act(async () => {
      renderForm((h) => {
        handle = h;
      });
    });

    expect(screen.getByText("esewaRedirectTitle")).toBeInTheDocument();
    expect(screen.getByText("esewaRedirectInfo")).toBeInTheDocument();
    expect(handle).not.toBeNull();
  });

  it("creates a session and auto-submits a hidden form POST on confirm", async () => {
    mockCreate.mockResolvedValue({ success: true, session: esewaSession });
    let handle: EsewaPaymentFormHandle | null = null;

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
    expect(mockCreate).toHaveBeenCalledWith("cart-1", "pm-esewa", {
      success_url: "https://shop.test/us/en/confirm-payment/cart-1",
      failure_url: "https://shop.test/us/en/confirm-payment/cart-1",
    });

    // Hidden form POST navigation (not fetch/XHR)
    const form = document.body.querySelector("form");
    expect(form?.getAttribute("method")?.toLowerCase()).toBe("post");
    expect(form?.getAttribute("action")).toBe(
      "https://rc-epay.esewa.com.np/api/epay/main/v2/form",
    );
    const inputs = Object.fromEntries(
      [...(form?.querySelectorAll("input") ?? [])].map((i) => [
        i.name,
        (i as HTMLInputElement).value,
      ]),
    );
    expect(inputs).toMatchObject({
      total_amount: "100",
      transaction_uuid: "txn-uuid-1",
      product_code: "EPAYTEST",
      signature: "c2lnbmF0dXJl",
      signed_field_names: "total_amount,transaction_uuid,product_code",
    });
    expect(submitSpy).toHaveBeenCalled();

    // Session id persisted for the confirm-payment return
    expect(window.sessionStorage.getItem("spree.redirect_session.cart-1")).toBe(
      JSON.stringify({ sessionId: "session-esewa", gateway: "esewa" }),
    );

    // Redirecting state shown
    expect(screen.getByText("redirectingToGateway:eSewa")).toBeInTheDocument();
  });

  it("returns a user-facing error when session creation fails", async () => {
    mockCreate.mockResolvedValue({
      success: false,
      error: "Gateway unavailable",
    });
    let handle: EsewaPaymentFormHandle | null = null;

    await act(async () => {
      renderForm((h) => {
        handle = h;
      });
    });

    let outcome: { error?: string } | undefined;
    await act(async () => {
      outcome = await handle!.confirmPayment("https://shop.test/return");
    });

    expect(outcome).toEqual({ error: "Gateway unavailable" });
    expect(submitSpy).not.toHaveBeenCalled();
    expect(
      window.sessionStorage.getItem("spree.redirect_session.cart-1"),
    ).toBeNull();
  });

  it("returns an error when the session has no form data", async () => {
    mockCreate.mockResolvedValue({
      success: true,
      session: { ...esewaSession, external_data: {} },
    });
    let handle: EsewaPaymentFormHandle | null = null;

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
    expect(submitSpy).not.toHaveBeenCalled();
  });
});
