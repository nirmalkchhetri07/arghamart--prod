import { describe, expect, it } from "vitest";
import {
  isRedirectGatewayId,
  resolveGatewayId,
} from "@/lib/utils/payment-gateway";

describe("resolveGatewayId", () => {
  it("resolves existing gateways", () => {
    expect(resolveGatewayId("stripe")).toBe("stripe");
    expect(resolveGatewayId("adyen")).toBe("adyen");
    expect(resolveGatewayId("paypal_checkout")).toBe("paypal");
    expect(resolveGatewayId("razorpay_checkout")).toBe("razorpay");
  });

  it("resolves eSewa type variants", () => {
    expect(resolveGatewayId("esewa")).toBe("esewa");
    expect(resolveGatewayId("Spree::PaymentMethod::Esewa")).toBe("esewa");
    expect(resolveGatewayId("SpreeEsewa::Gateway")).toBe("esewa");
    expect(resolveGatewayId("Spree::Gateway::EsewaGateway")).toBe("esewa");
  });

  it("resolves Khalti type variants", () => {
    expect(resolveGatewayId("khalti")).toBe("khalti");
    expect(resolveGatewayId("Spree::PaymentMethod::Khalti")).toBe("khalti");
    expect(resolveGatewayId("SpreeKhalti::Gateway")).toBe("khalti");
    expect(resolveGatewayId("Spree::Gateway::KhaltiGateway")).toBe("khalti");
  });

  it("falls back to substring matching for unknown eSewa/Khalti class names", () => {
    expect(resolveGatewayId("Spree::PaymentMethod::ESEWA")).toBe("esewa");
    expect(resolveGatewayId("Spree::PaymentMethod::KhaltiTest")).toBe("khalti");
  });

  it("resolves Manual QR type variants", () => {
    expect(resolveGatewayId("manual_qr")).toBe("manual_qr");
    expect(resolveGatewayId("Spree::PaymentMethod::ManualQr")).toBe(
      "manual_qr",
    );
  });

  it("returns unknown for unrecognised gateways", () => {
    expect(resolveGatewayId("Spree::Gateway::Bogus")).toBe("unknown");
    expect(resolveGatewayId("check")).toBe("unknown");
  });
});

describe("isRedirectGatewayId", () => {
  it("is true for esewa and khalti only (manual_qr stays in-page)", () => {
    expect(isRedirectGatewayId("esewa")).toBe(true);
    expect(isRedirectGatewayId("khalti")).toBe(true);
    expect(isRedirectGatewayId("manual_qr")).toBe(false);
    expect(isRedirectGatewayId("stripe")).toBe(false);
    expect(isRedirectGatewayId("adyen")).toBe(false);
    expect(isRedirectGatewayId("paypal")).toBe(false);
    expect(isRedirectGatewayId("razorpay")).toBe(false);
    expect(isRedirectGatewayId("unknown")).toBe(false);
  });
});
