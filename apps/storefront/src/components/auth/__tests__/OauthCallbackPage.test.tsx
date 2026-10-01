import { render, screen, waitFor } from "@testing-library/react";
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
}));

const refreshUser = vi.fn();
const replace = vi.fn();

let mockParams = { provider: "github" };
let mockSearch = new URLSearchParams();
let mockPathname = "/us/en/auth/callback/github";

vi.mock("@/contexts/AuthContext", () => ({
  useAuth: () => ({ refreshUser }),
}));

vi.mock("next/navigation", () => ({
  useRouter: () => ({ replace, push: vi.fn() }),
  usePathname: () => mockPathname,
  useParams: () => mockParams,
  useSearchParams: () => mockSearch,
}));

import OauthCallbackPage from "@/app/[country]/[locale]/(storefront)/auth/callback/[provider]/page";
import { createOauthState } from "@/lib/auth/oauth-client";
import { oauthLogin } from "@/lib/data/oauth";

const mockOauthLogin = vi.mocked(oauthLogin);

function seedState(next: string | null) {
  const { state, nonce } = createOauthState(next);
  sessionStorage.setItem("oauth:state:github", nonce);
  return state;
}

describe("OauthCallbackPage", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    sessionStorage.clear();
    mockParams = { provider: "github" };
    mockSearch = new URLSearchParams();
    mockPathname = "/us/en/auth/callback/github";
  });

  it("exchanges the GitHub code and lands on the return target", async () => {
    const state = seedState("/us/en/account/orders");
    mockSearch = new URLSearchParams({ code: "auth-code-1", state });
    mockOauthLogin.mockResolvedValue({
      success: true,
      user: { id: "u1", email: "a@example.com" },
    });

    render(<OauthCallbackPage />);
    await waitFor(() => expect(mockOauthLogin).toHaveBeenCalled());

    expect(mockOauthLogin).toHaveBeenCalledWith(
      "github",
      "auth-code-1",
      `${window.location.origin}/us/en/auth/callback/github`,
    );
    expect(refreshUser).toHaveBeenCalled();
    expect(replace).toHaveBeenCalledWith("/us/en/account/orders");
    expect(sessionStorage.getItem("oauth:state:github")).toBeNull();
  });

  it("shows a cancelled message when the provider reports an error", async () => {
    mockSearch = new URLSearchParams({ error: "access_denied" });

    render(<OauthCallbackPage />);
    await waitFor(() =>
      expect(screen.getByText("errors.cancelled")).toBeInTheDocument(),
    );

    expect(mockOauthLogin).not.toHaveBeenCalled();
    expect(replace).not.toHaveBeenCalled();
  });

  it("rejects a mismatched state nonce", async () => {
    const { state } = createOauthState("/us/en/account/orders");
    sessionStorage.setItem("oauth:state:github", "different-nonce");
    mockSearch = new URLSearchParams({ code: "auth-code-1", state });

    render(<OauthCallbackPage />);
    await waitFor(() =>
      expect(screen.getByText("errors.failed")).toBeInTheDocument(),
    );

    expect(mockOauthLogin).not.toHaveBeenCalled();
  });

  it("rejects an unknown provider", async () => {
    mockParams = { provider: "myspace" };
    mockSearch = new URLSearchParams({ code: "x", state: "y" });

    render(<OauthCallbackPage />);
    await waitFor(() =>
      expect(screen.getByText("errors.failed")).toBeInTheDocument(),
    );

    expect(mockOauthLogin).not.toHaveBeenCalled();
  });

  it("shows the localized API error when the exchange fails", async () => {
    const state = seedState("/us/en/account");
    mockSearch = new URLSearchParams({ code: "stale-code", state });
    mockOauthLogin.mockResolvedValue({
      success: false,
      errorCode: "invalid_token",
    });

    render(<OauthCallbackPage />);
    await waitFor(() =>
      expect(screen.getByText("errors.invalid_token")).toBeInTheDocument(),
    );

    expect(screen.getByText("backToSignIn")).toBeInTheDocument();
  });
});
