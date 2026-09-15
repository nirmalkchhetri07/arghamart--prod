import { beforeEach, describe, expect, it } from "vitest";
import {
  clearRedirectSession,
  readRedirectSession,
  saveRedirectSession,
} from "@/lib/utils/redirect-payment-session";

describe("redirect-payment-session", () => {
  beforeEach(() => {
    window.sessionStorage.clear();
    window.localStorage.clear();
  });

  it("round-trips a saved session ref", () => {
    saveRedirectSession("cart-1", { sessionId: "session-1", gateway: "esewa" });

    expect(readRedirectSession("cart-1")).toEqual({
      sessionId: "session-1",
      gateway: "esewa",
    });
  });

  it("falls back to localStorage when sessionStorage is empty", () => {
    saveRedirectSession("cart-1", {
      sessionId: "session-9",
      gateway: "khalti",
    });
    window.sessionStorage.clear();

    expect(readRedirectSession("cart-1")).toEqual({
      sessionId: "session-9",
      gateway: "khalti",
    });
  });

  it("returns null when nothing was saved", () => {
    expect(readRedirectSession("cart-missing")).toBeNull();
  });

  it("returns null for malformed payloads", () => {
    window.sessionStorage.setItem("spree.redirect_session.cart-1", "not-json");
    expect(readRedirectSession("cart-1")).toBeNull();

    window.sessionStorage.setItem(
      "spree.redirect_session.cart-1",
      JSON.stringify({ sessionId: "", gateway: "esewa" }),
    );
    expect(readRedirectSession("cart-1")).toBeNull();

    window.sessionStorage.setItem(
      "spree.redirect_session.cart-1",
      JSON.stringify({ sessionId: "s-1", gateway: "stripe" }),
    );
    expect(readRedirectSession("cart-1")).toBeNull();
  });

  it("clears the stored ref from both storages", () => {
    saveRedirectSession("cart-1", { sessionId: "session-1", gateway: "esewa" });
    clearRedirectSession("cart-1");

    expect(readRedirectSession("cart-1")).toBeNull();
  });

  it("isolates refs per cart", () => {
    saveRedirectSession("cart-1", { sessionId: "session-1", gateway: "esewa" });

    expect(readRedirectSession("cart-2")).toBeNull();
  });
});
