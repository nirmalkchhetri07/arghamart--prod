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
  completeOauthLogin: vi.fn(),
}));

vi.mock("@/lib/auth/facebook", () => ({
  loadFacebookSdk: vi.fn().mockResolvedValue({}),
  isFacebookInAppBrowser: vi.fn().mockReturnValue(false),
  facebookPopupLogin: vi.fn(),
  facebookRedirectUri: (origin: string) => `${origin}/fb-callback`,
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
import {
  facebookPopupLogin,
  isFacebookInAppBrowser,
} from "@/lib/auth/facebook";
import {
  completeOauthLogin,
  getOauthProviders,
  oauthLogin,
} from "@/lib/data/oauth";
import { SocialLoginButtons } from "../SocialLoginButtons";

const mockProviders = vi.mocked(getOauthProviders);
const mockOauthLogin = vi.mocked(oauthLogin);
const mockCompleteOauthLogin = vi.mocked(completeOauthLogin);
const mockPopupLogin = vi.mocked(facebookPopupLogin);
const mockInAppBrowser = vi.mocked(isFacebookInAppBrowser);
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
  // defineProperty avoids the global `Window["google"]` type (which merges
  // with an unrelated global `google`) — the mock only needs runtime shape.
  Object.defineProperty(window, "google", {
    value: {
      accounts: { id: { initialize, renderButton: vi.fn() } },
    },
    configurable: true,
    writable: true,
  });
  return initialize;
}

/** Replace window.location with a plain object so href assignments can be
 * asserted without jsdom attempting navigation. */
function stubLocation() {
  const originalLocation = window.location;
  Object.defineProperty(window, "location", {
    value: { origin: "https://shop.example", href: "" },
    writable: true,
    configurable: true,
  });
  return () =>
    Object.defineProperty(window, "location", {
      value: originalLocation,
      writable: true,
      configurable: true,
    });
}

describe("SocialLoginButtons", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    Reflect.deleteProperty(window, "google");
    sessionStorage.clear();
    mockInAppBrowser.mockReturnValue(false);
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

  it("opens the inline form when Google hits a pending code", async () => {
    const initialize = mockGsi();
    mockProviders.mockResolvedValue([GOOGLE]);
    mockOauthLogin.mockResolvedValue({
      success: false,
      errorCode: "account_exists_confirm_required",
      pendingOAuth: "pending-google",
    });

    render(<SocialLoginButtons redirectUrl={null} />);
    await waitFor(() => expect(initialize).toHaveBeenCalled());

    const callback: GsiCallback = initialize.mock.calls[0][0].callback;
    await callback({ credential: "id-token-jwt" });

    expect(await screen.findByText("accountExistsTitle")).toBeInTheDocument();
    expect(screen.getByText("passwordLabel")).toBeInTheDocument();
    expect(screen.queryByText("orContinueWith")).not.toBeInTheDocument();
    expect(mockToastError).not.toHaveBeenCalled();
  });

  it("renders Facebook and GitHub buttons for enabled providers", async () => {
    mockProviders.mockResolvedValue([FACEBOOK, GITHUB]);

    render(<SocialLoginButtons redirectUrl={null} />);
    await waitFor(() => expect(mockProviders).toHaveBeenCalled());

    expect(screen.getByText("continueWithFacebook")).toBeInTheDocument();
    expect(screen.getByText("continueWithGitHub")).toBeInTheDocument();
  });

  it("signs in through the Facebook popup with the access token", async () => {
    mockProviders.mockResolvedValue([FACEBOOK]);
    mockPopupLogin.mockResolvedValue({ token: "fb-access-token" });
    mockOauthLogin.mockResolvedValue({
      success: true,
      user: { id: "u1", email: "fb@example.com" },
    });

    render(<SocialLoginButtons redirectUrl="/us/en/account" />);
    await waitFor(() => expect(mockProviders).toHaveBeenCalled());

    fireEvent.click(screen.getByText("continueWithFacebook"));

    await waitFor(() =>
      expect(mockOauthLogin).toHaveBeenCalledWith(
        "facebook",
        "fb-access-token",
      ),
    );
    expect(sessionStorage.getItem("oauth:state:facebook")).toBeTruthy();
    expect(sessionStorage.getItem("oauth:returnTo:facebook")).toBe(
      "/us/en/account",
    );
    expect(refreshUser).toHaveBeenCalled();
    expect(push).toHaveBeenCalledWith("/us/en/account");
  });

  it("redirects to the Facebook dialog inside an in-app browser", async () => {
    mockProviders.mockResolvedValue([FACEBOOK]);
    mockInAppBrowser.mockReturnValue(true);
    const restoreLocation = stubLocation();

    try {
      render(<SocialLoginButtons redirectUrl="/us/en/account/orders" />);
      await waitFor(() => expect(mockProviders).toHaveBeenCalled());

      fireEvent.click(screen.getByText("continueWithFacebook"));

      await waitFor(() =>
        expect(String(window.location.href)).toContain(
          "facebook.com/v20.0/dialog/oauth",
        ),
      );
      const url = new URL(window.location.href as string);
      expect(url.searchParams.get("client_id")).toBe("fb-app-id");
      expect(url.searchParams.get("response_type")).toBe("token");
      expect(url.searchParams.get("redirect_uri")).toBe(
        "https://shop.example/fb-callback",
      );
      const stored = sessionStorage.getItem("oauth:state:facebook");
      expect(stored).toBeTruthy();
      const { parseOauthState } = await import("@/lib/auth/oauth-client");
      expect(parseOauthState(url.searchParams.get("state"))).toEqual({
        next: "/us/en/account/orders",
        nonce: stored,
      });
      expect(mockPopupLogin).not.toHaveBeenCalled();
      expect(mockOauthLogin).not.toHaveBeenCalled();
    } finally {
      restoreLocation();
    }
  });

  it("falls back to the dialog redirect when the popup is unavailable", async () => {
    mockProviders.mockResolvedValue([FACEBOOK]);
    mockPopupLogin.mockResolvedValue("unavailable");
    const restoreLocation = stubLocation();

    try {
      render(<SocialLoginButtons redirectUrl={null} />);
      await waitFor(() => expect(mockProviders).toHaveBeenCalled());

      fireEvent.click(screen.getByText("continueWithFacebook"));

      await waitFor(() =>
        expect(String(window.location.href)).toContain(
          "facebook.com/v20.0/dialog/oauth",
        ),
      );
      expect(mockOauthLogin).not.toHaveBeenCalled();
    } finally {
      restoreLocation();
    }
  });

  it("toasts when the Facebook dialog is cancelled", async () => {
    mockProviders.mockResolvedValue([FACEBOOK]);
    mockPopupLogin.mockResolvedValue("cancelled");

    render(<SocialLoginButtons redirectUrl={null} />);
    await waitFor(() => expect(mockProviders).toHaveBeenCalled());

    fireEvent.click(screen.getByText("continueWithFacebook"));

    await waitFor(() =>
      expect(mockToastError).toHaveBeenCalledWith("errors.cancelled"),
    );
    expect(mockOauthLogin).not.toHaveBeenCalled();
  });

  it("collects a missing email inline and completes the sign-in", async () => {
    mockProviders.mockResolvedValue([FACEBOOK]);
    mockPopupLogin.mockResolvedValue({ token: "fb-token" });
    mockOauthLogin.mockResolvedValue({
      success: false,
      errorCode: "email_missing",
      pendingOAuth: "pending-1",
    });
    mockCompleteOauthLogin.mockResolvedValue({
      success: true,
      user: { id: "u2", email: "new@example.com" },
    });

    render(<SocialLoginButtons redirectUrl={null} />);
    await waitFor(() => expect(mockProviders).toHaveBeenCalled());

    fireEvent.click(screen.getByText("continueWithFacebook"));
    expect(await screen.findByText("emailMissingTitle")).toBeInTheDocument();
    expect(screen.queryByText("continueWithFacebook")).not.toBeInTheDocument();

    fireEvent.change(screen.getByLabelText("emailLabel"), {
      target: { value: "new@example.com" },
    });
    fireEvent.click(screen.getByText("continueSignIn"));

    await waitFor(() =>
      expect(mockCompleteOauthLogin).toHaveBeenCalledWith({
        pendingOAuth: "pending-1",
        email: "new@example.com",
      }),
    );
    expect(refreshUser).toHaveBeenCalled();
    expect(push).toHaveBeenCalledWith("/us/en/account");
  });

  it("asks for the password when the email already belongs to an account", async () => {
    mockProviders.mockResolvedValue([FACEBOOK]);
    mockPopupLogin.mockResolvedValue({ token: "fb-token" });
    mockOauthLogin.mockResolvedValue({
      success: false,
      errorCode: "account_exists_confirm_required",
      pendingOAuth: "pending-2",
    });
    mockCompleteOauthLogin.mockResolvedValue({
      success: false,
      errorCode: "invalid_credentials",
    });

    render(<SocialLoginButtons redirectUrl={null} />);
    await waitFor(() => expect(mockProviders).toHaveBeenCalled());

    fireEvent.click(screen.getByText("continueWithFacebook"));
    expect(await screen.findByText("accountExistsTitle")).toBeInTheDocument();

    fireEvent.change(screen.getByLabelText("passwordLabel"), {
      target: { value: "wrong-password" },
    });
    fireEvent.click(screen.getByText("continueSignIn"));

    await waitFor(() =>
      expect(mockCompleteOauthLogin).toHaveBeenCalledWith({
        pendingOAuth: "pending-2",
        password: "wrong-password",
      }),
    );
    expect(await screen.findByRole("alert")).toHaveTextContent(
      "errors.invalid_credentials",
    );
    expect(push).not.toHaveBeenCalled();
  });

  it("rotates the form to password mode when the typed email is taken", async () => {
    mockProviders.mockResolvedValue([FACEBOOK]);
    mockPopupLogin.mockResolvedValue({ token: "fb-token" });
    mockOauthLogin.mockResolvedValue({
      success: false,
      errorCode: "email_missing",
      pendingOAuth: "pending-3",
    });
    mockCompleteOauthLogin.mockResolvedValue({
      success: false,
      errorCode: "account_exists_confirm_required",
      pendingOAuth: "pending-4",
    });

    render(<SocialLoginButtons redirectUrl={null} />);
    await waitFor(() => expect(mockProviders).toHaveBeenCalled());

    fireEvent.click(screen.getByText("continueWithFacebook"));
    expect(await screen.findByText("emailMissingTitle")).toBeInTheDocument();

    fireEvent.change(screen.getByLabelText("emailLabel"), {
      target: { value: "taken@example.com" },
    });
    fireEvent.click(screen.getByText("continueSignIn"));

    expect(await screen.findByText("accountExistsTitle")).toBeInTheDocument();
    expect(mockCompleteOauthLogin).toHaveBeenCalledWith({
      pendingOAuth: "pending-3",
      email: "taken@example.com",
    });
  });

  it("redirects to the GitHub dialog", async () => {
    mockProviders.mockResolvedValue([GITHUB]);
    const restoreLocation = stubLocation();

    try {
      render(<SocialLoginButtons redirectUrl={null} />);
      await waitFor(() => expect(mockProviders).toHaveBeenCalled());

      fireEvent.click(screen.getByText("continueWithGitHub"));

      await waitFor(() =>
        expect(String(window.location.href)).toContain(
          "github.com/login/oauth/authorize",
        ),
      );
      const url = new URL(window.location.href as string);
      expect(url.searchParams.get("client_id")).toBe("gh-client-id");
      expect(url.searchParams.get("redirect_uri")).toBe(
        "https://shop.example/us/en/auth/callback/github",
      );
      expect(sessionStorage.getItem("oauth:state:github")).toBeTruthy();
    } finally {
      restoreLocation();
    }
  });
});
