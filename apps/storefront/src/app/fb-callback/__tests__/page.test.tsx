import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";

vi.mock("next-intl", async () => {
  const actual = await vi.importActual("next-intl");
  return {
    ...actual,
    useTranslations: () => (key: string) => key,
  };
});

vi.mock("@/lib/data/oauth", () => ({
  oauthLogin: vi.fn(),
  completeOauthLogin: vi.fn(),
}));

const replace = vi.fn();
const push = vi.fn();

vi.mock("next/navigation", () => ({
  useRouter: () => ({ replace, push }),
}));

import FbCallbackPage from "@/app/fb-callback/page";
import { createOauthState } from "@/lib/auth/oauth-client";
import { completeOauthLogin, oauthLogin } from "@/lib/data/oauth";

const mockOauthLogin = vi.mocked(oauthLogin);
const mockComplete = vi.mocked(completeOauthLogin);

function seedState(next: string | null): string {
  const { state, nonce } = createOauthState(next);
  sessionStorage.setItem("oauth:state:facebook", nonce);
  sessionStorage.setItem("oauth:returnTo:facebook", next ?? "");
  return state;
}

function clearMarketCookies() {
  for (const name of ["spree_country", "spree_locale"]) {
    // biome-ignore lint/suspicious/noDocumentCookie: jsdom has no Cookie Store API; tests seed market cookies directly
    document.cookie = `${name}=; max-age=0; path=/`;
  }
}

describe("FbCallbackPage", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    sessionStorage.clear();
    clearMarketCookies();
    window.location.hash = "";
  });

  it("exchanges the access token and lands on the return target", async () => {
    const state = seedState("/us/en/account/orders");
    window.location.hash = `#access_token=fb-token&state=${state}`;
    mockOauthLogin.mockResolvedValue({
      success: true,
      user: { id: "u1", email: "a@example.com" },
    });

    render(<FbCallbackPage />);
    await waitFor(() =>
      expect(mockOauthLogin).toHaveBeenCalledWith("facebook", "fb-token"),
    );

    expect(replace).toHaveBeenCalledWith("/us/en/account/orders");
    expect(sessionStorage.getItem("oauth:state:facebook")).toBeNull();
  });

  it("falls back to the market cookies for the default destination", async () => {
    // biome-ignore lint/suspicious/noDocumentCookie: jsdom has no Cookie Store API; tests seed market cookies directly
    document.cookie = "spree_country=ne; path=/";
    // biome-ignore lint/suspicious/noDocumentCookie: jsdom has no Cookie Store API; tests seed market cookies directly
    document.cookie = "spree_locale=ne; path=/";
    const state = seedState(null);
    window.location.hash = `#access_token=fb-token&state=${state}`;
    mockOauthLogin.mockResolvedValue({
      success: true,
      user: { id: "u1", email: "a@example.com" },
    });

    render(<FbCallbackPage />);
    await waitFor(() => expect(replace).toHaveBeenCalledWith("/ne/ne/account"));
  });

  it("rejects a missing or mismatched state nonce", async () => {
    sessionStorage.setItem("oauth:state:facebook", "different-nonce");
    const { state } = createOauthState("/us/en/account");
    window.location.hash = `#access_token=fb-token&state=${state}`;

    render(<FbCallbackPage />);
    await waitFor(() =>
      expect(screen.getByText("errors.failed")).toBeInTheDocument(),
    );

    expect(mockOauthLogin).not.toHaveBeenCalled();
    expect(replace).not.toHaveBeenCalled();
  });

  it("rejects a response without an access token", async () => {
    const state = seedState(null);
    window.location.hash = `#state=${state}`;

    render(<FbCallbackPage />);
    await waitFor(() =>
      expect(screen.getByText("errors.failed")).toBeInTheDocument(),
    );

    expect(mockOauthLogin).not.toHaveBeenCalled();
  });

  it("shows the cancelled message when the dialog reports an error", async () => {
    window.location.hash = "#error=access_denied";

    render(<FbCallbackPage />);
    await waitFor(() =>
      expect(screen.getByText("errors.cancelled")).toBeInTheDocument(),
    );

    expect(mockOauthLogin).not.toHaveBeenCalled();
  });

  it("shows a localized error when the exchange fails", async () => {
    const state = seedState(null);
    window.location.hash = `#access_token=stale-token&state=${state}`;
    mockOauthLogin.mockResolvedValue({
      success: false,
      errorCode: "invalid_token",
    });

    render(<FbCallbackPage />);
    await waitFor(() =>
      expect(screen.getByText("errors.invalid_token")).toBeInTheDocument(),
    );

    expect(screen.getByText("backToSignIn")).toBeInTheDocument();
  });

  it("collects a missing email inline and completes on the page", async () => {
    const state = seedState(null);
    window.location.hash = `#access_token=fb-token&state=${state}`;
    mockOauthLogin.mockResolvedValue({
      success: false,
      errorCode: "email_missing",
      pendingOAuth: "pending-1",
    });
    mockComplete.mockResolvedValue({
      success: true,
      user: { id: "u2", email: "new@example.com" },
    });

    render(<FbCallbackPage />);
    expect(await screen.findByText("emailMissingTitle")).toBeInTheDocument();

    fireEvent.change(screen.getByLabelText("emailLabel"), {
      target: { value: "new@example.com" },
    });
    fireEvent.click(screen.getByText("continueSignIn"));

    await waitFor(() =>
      expect(mockComplete).toHaveBeenCalledWith({
        pendingOAuth: "pending-1",
        email: "new@example.com",
      }),
    );
    expect(replace).toHaveBeenCalledWith("/us/en/account");
  });
});
