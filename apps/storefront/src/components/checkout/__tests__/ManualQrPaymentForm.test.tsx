import { act, render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";

vi.mock("next-intl", async () => {
  const actual = await vi.importActual("next-intl");
  return {
    ...actual,
    useTranslations: () => (key: string, values?: Record<string, string>) => {
      if (values?.amount) return `${key}:${values.amount}:${values.currency}`;
      return key;
    },
  };
});

vi.mock("@/lib/data/payment", () => ({
  completeCheckoutPaymentSession: vi.fn(),
  uploadManualQrProof: vi.fn(),
}));

import {
  completeCheckoutPaymentSession,
  uploadManualQrProof,
} from "@/lib/data/payment";
import type { PaymentSession } from "@spree/sdk";
import {
  ManualQrPaymentForm,
  type ManualQrPaymentFormHandle,
} from "../ManualQrPaymentForm";

const mockUpload = vi.mocked(uploadManualQrProof);
const mockComplete = vi.mocked(completeCheckoutPaymentSession);

function renderForm(onReady: (handle: ManualQrPaymentFormHandle) => void) {
  return render(
    <ManualQrPaymentForm
      cartId="cart-1"
      sessionId="session-qr"
      qrImageUrl="https://api.test/rails/active_storage/qr.png"
      instructions="Pay to ArghaMart."
      amountDue="1500.00"
      currency="NPR"
      onReady={onReady}
    />,
  );
}

function pngFile(name = "proof.png", size = 1024): File {
  const bytes = new Uint8Array(size);
  return new File([bytes], name, { type: "image/png" });
}

describe("ManualQrPaymentForm", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("renders the QR, amount and instructions and registers its handle", async () => {
    let handle: ManualQrPaymentFormHandle | null = null;

    await act(async () => {
      renderForm((h) => {
        handle = h;
      });
    });

    expect(screen.getByText("manualQrTitle")).toBeInTheDocument();
    expect(
      screen.getByText("manualQrAmountDue:1500.00:NPR"),
    ).toBeInTheDocument();
    expect(screen.getByText("Pay to ArghaMart.")).toBeInTheDocument();
    expect(handle).not.toBeNull();
  });

  it("requires a screenshot before submitting", async () => {
    mockUpload.mockResolvedValue({ success: true });
    mockComplete.mockResolvedValue({
      success: true,
      session: { status: "completed" } as unknown as PaymentSession,
    });
    let handle: ManualQrPaymentFormHandle | null = null;

    await act(async () => {
      renderForm((h) => {
        handle = h;
      });
    });

    let outcome: { error?: string } | undefined;
    await act(async () => {
      outcome = await handle!.confirmPayment("https://shop.test/return");
    });

    expect(outcome).toEqual({ error: "manualQrNoFile" });
    expect(mockUpload).not.toHaveBeenCalled();
    expect(mockComplete).not.toHaveBeenCalled();
  });

  it("uploads the proof and completes the session on confirm", async () => {
    mockUpload.mockResolvedValue({ success: true });
    mockComplete.mockResolvedValue({
      success: true,
      session: { status: "completed" } as unknown as PaymentSession,
    });
    let handle: ManualQrPaymentFormHandle | null = null;

    await act(async () => {
      renderForm((h) => {
        handle = h;
      });
    });

    const input = document.getElementById(
      "manual-qr-proof",
    ) as HTMLInputElement;
    const user = userEvent.setup();
    await act(async () => {
      await user.upload(input, pngFile());
    });

    let outcome: { error?: string } | undefined;
    await act(async () => {
      outcome = await handle!.confirmPayment("https://shop.test/return");
    });

    expect(outcome).toEqual({});
    expect(mockUpload).toHaveBeenCalledWith(
      "cart-1",
      "session-qr",
      expect.any(File),
    );
    expect(mockComplete).toHaveBeenCalledWith(
      "cart-1",
      "session-qr",
      undefined,
    );
  });

  it("forwards the transaction ID when entered", async () => {
    mockUpload.mockResolvedValue({ success: true });
    mockComplete.mockResolvedValue({
      success: true,
      session: { status: "completed" } as unknown as PaymentSession,
    });
    let handle: ManualQrPaymentFormHandle | null = null;

    await act(async () => {
      renderForm((h) => {
        handle = h;
      });
    });

    const user = userEvent.setup();
    await act(async () => {
      await user.upload(
        document.getElementById("manual-qr-proof") as HTMLInputElement,
        pngFile(),
      );
      await user.type(
        screen.getByPlaceholderText("manualQrTransactionPlaceholder"),
        "TXN123",
      );
    });

    await act(async () => {
      await handle!.confirmPayment("https://shop.test/return");
    });

    expect(mockComplete).toHaveBeenCalledWith("cart-1", "session-qr", {
      external_data: { transaction_id: "TXN123" },
    });
  });

  it("returns the upload error without completing", async () => {
    mockUpload.mockResolvedValue({ success: false, error: "Too big" });
    let handle: ManualQrPaymentFormHandle | null = null;

    await act(async () => {
      renderForm((h) => {
        handle = h;
      });
    });

    const user = userEvent.setup();
    await act(async () => {
      await user.upload(
        document.getElementById("manual-qr-proof") as HTMLInputElement,
        pngFile(),
      );
    });

    let outcome: { error?: string } | undefined;
    await act(async () => {
      outcome = await handle!.confirmPayment("https://shop.test/return");
    });

    expect(outcome).toEqual({ error: "Too big" });
    expect(mockComplete).not.toHaveBeenCalled();
  });

  it("clears a shown error via clearError", async () => {
    mockUpload.mockResolvedValue({ success: false, error: "Too big" });
    let handle: ManualQrPaymentFormHandle | null = null;

    await act(async () => {
      renderForm((h) => {
        handle = h;
      });
    });

    const user = userEvent.setup();
    await act(async () => {
      await user.upload(
        document.getElementById("manual-qr-proof") as HTMLInputElement,
        pngFile(),
      );
    });
    await act(async () => {
      await handle!.confirmPayment("https://shop.test/return");
    });
    expect(screen.getByText("Too big")).toBeInTheDocument();

    await act(async () => {
      handle!.clearError();
    });
    expect(screen.queryByText("Too big")).toBeNull();
  });
});
