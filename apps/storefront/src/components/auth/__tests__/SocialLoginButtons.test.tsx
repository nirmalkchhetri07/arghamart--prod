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
  getOauthProviders: vi.fn(),
  oauthLogin: vi.fn(),
}));

const refreshUser = vi.fn();
const push = vi.fn();

vi.mock("@/contexts/AuthContext", () => ({
  useAuth: () => ({ refreshUser }),
}));

vi.mock("next/navigation", () => ({
  useRouter: () => ({ push }),
  usePathname: () => "/us/en/account",
  useSearchParams: () => new URLSearchParams(),
}));

vi.mock("sonner", () => ({
  toast: { error: vi.fn(), success: vi.fn() },
}));

import { toast } from "sonner";
import { getOauthProviders, oauthLogin } from "@/lib/data/oauth";
import { SocialLoginButtons } from "../SocialLoginButtons";

const mockProviders = vi.mocked(getOauthProviders);
const mockOauthLogin = vi.mocked(oauthLogin);
const mockToastError = vi.mocked(toast.error);

const GOOGLE = {
  provider: "google",
  name: "Google",
  client_id: "test.apps.googleusercontent.com",
};

const FACEBOOK = {
  provider: "facebook",
  name: "Facebook",
  client_id: "fb-app-id",
};

const GITHUB = {
  provider: "github",
  name: "GitHub",
  client_id: "gh-client-id",
};

type GsiCallback = (response: { credential: string }) => void;

function mockGsi() {
  const initialize = vi.fn();
  window.google = {
    accounts: { id: { initialize, renderButton: vi.fn() } },
  } as unknown as Window["google"];
  return initialize;
}

describe("SocialLoginButtons", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    delete window.google;
  });

  it("renders nothing when no providers are enabled", async () => {
    mockProviders.mockResolvedValue([]);

    const { container } = render(<SocialLoginButtons redirectUrl={null} />);
    await waitFor(() => expect(mockProviders).toHaveBeenCalled());

    expect(container).toBeEmptyDOMElement();
  });

  it("renders the Google button for an enabled Google provider", async () => {
    const initialize = mockGsi();
    mockProviders.mockResolvedValue([GOOGLE]);

    render(<SocialLoginButtons redirectUrl={null} />);
    await waitFor(() => expect(initialize).toHaveBeenCalled());

    expect(initialize).toHaveBeenCalledWith(
      expect.objectContaining({ client_id: GOOGLE.client_id }),
    );
    expect(window.google?.accounts.id.renderButton).toHaveBeenCalled();
    expect(screen.getByText("orContinueWith")).toBeInTheDocument();
  });

  it("ignores unknown providers", async () => {
    const initialize = mockGsi();
    mockProviders.mockResolvedValue([
      GOOGLE,
      { provider: "myspace", name: "Myspace", client_id: "x" },
    ]);

    render(<SocialLoginButtons redirectUrl={null} />);
    await waitFor(() => expect(initialize).toHaveBeenCalledTimes(1));

    expect(screen.queryByText("myspace")).not.toBeInTheDocument();
  });

  it("signs in on GIS callback and redirects", async () => {
    const initialize = mockGsi();
    mockProviders.mockResolvedValue([GOOGLE]);
    mockOauthLogin.mockResolvedValue({
      success: true,
      user: { id: "u1", email: "g@example.com" },
    });

    render(<SocialLoginButtons redirectUrl="/us/en/account" />);
    await waitFor(() => expect(initialize).toHaveBeenCalled());

    const callback: GsiCallback = initialize.mock.calls[0][0].callback;
    await callback({ credential: "id-token-jwt" });

    expect(mockOauthLogin).toHaveBeenCalledWith("google", "id-token-jwt");
    expect(refreshUser).toHaveBeenCalled();
    expect(push).toHaveBeenCalledWith("/us/en/account");
  });

  it("toasts a localized error when sign-in fails", async () => {
    const initialize = mockGsi();
    mockProviders.mockResolvedValue([GOOGLE]);
    mockOauthLogin.mockResolvedValue({
      success: false,
      errorCode: "invalid_token",
    });

    render(<SocialLoginButtons redirectUrl={null} />);
    await waitFor(() => expect(initialize).toHaveBeenCalled());

    const callback: GsiCallback = initialize.mock.calls[0][0].callback;
    await callback({ credential: "bad-token" });

    expect(mockToastError).toHaveBeenCalledWith("errors.invalid_token");
    expect(push).not.toHaveBeenCalled();
  });

  it("renders Facebook and GitHub buttons for enabled code providers", async () => {
    mockProviders.mockResolvedValue([FACEBOOK, GITHUB]);

    render(<SocialLoginButtons redirectUrl={null} />);
    await waitFor(() => expect(mockProviders).toHaveBeenCalled());

    expect(screen.getByText("continueWithFacebook")).toBeInTheDocument();
    expect(screen.getByText("continueWithGitHub")).toBeInTheDocument();
  });

  it("redirects to the Facebook dialog with state and stores the nonce", async () => {
    mockProviders.mockResolvedValue([FACEBOOK]);
    const originalLocation = window.location;
    Object.defineProperty(window, "location", {
      value: { origin: "https://shop.example", href: "" },
      writable: true,
      configurable: true,
    });

    try {
      render(<SocialLoginButtons redirectUrl="/us/en/account/orders" />);
      await waitFor(() => expect(mockProviders).toHaveBeenCalled());

      fireEvent.click(screen.getByText("continueWithFacebook"));

      const href: string = window.location.href;
      const url = new URL(href);
      expect(`${url.origin}${url.pathname}`).toBe(
        "https://www.facebook.com/v20.0/dialog/oauth",
      );
      expect(url.searchParams.get("client_id")).toBe("fb-app-id");
      expect(url.searchParams.get("redirect_uri")).toBe(
        "https://shop.example/us/en/auth/callback/facebook",
      );
      const stored = sessionStorage.getItem("oauth:state:facebook");
      expect(stored).toBeTruthy();
      const { parseOauthState } = await import("@/lib/auth/oauth-client");
      expect(parseOauthState(url.searchParams.get("state"))).toEqual({
        next: "/us/en/account/orders",
        nonce: stored,
      });
    } finally {
      Object.defineProperty(window, "location", {
        value: originalLocation,
        writable: true,
        configurable: true,
      });
      sessionStorage.clear();
    }
  });

  it("redirects to the GitHub dialog", async () => {
    mockProviders.mockResolvedValue([GITHUB]);
    const originalLocation = window.location;
    Object.defineProperty(window, "location", {
      value: { origin: "https://shop.example", href: "" },
      writable: true,
      configurable: true,
    });

    try {
      render(<SocialLoginButtons redirectUrl={null} />);
      await waitFor(() => expect(mockProviders).toHaveBeenCalled());

      fireEvent.click(screen.getByText("continueWithGitHub"));

      const url = new URL(window.location.href as string);
      expect(`${url.origin}${url.pathname}`).toBe(
        "https://github.com/login/oauth/authorize",
      );
      expect(url.searchParams.get("client_id")).toBe("gh-client-id");
      expect(url.searchParams.get("redirect_uri")).toBe(
        "https://shop.example/us/en/auth/callback/github",
      );
      expect(sessionStorage.getItem("oauth:state:github")).toBeTruthy();
    } finally {
      Object.defineProperty(window, "location", {
        value: originalLocation,
        writable: true,
        configurable: true,
      });
      sessionStorage.clear();
    }
  });
});
