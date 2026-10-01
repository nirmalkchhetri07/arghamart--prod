import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { FacebookSdk } from "../facebook";
import { facebookRedirectUri, isFacebookInAppBrowser } from "../facebook";

type FacebookModule = typeof import("../facebook");

let mod: FacebookModule;

const originalOpen = Object.getOwnPropertyDescriptor(window, "open");
const originalLocation = Object.getOwnPropertyDescriptor(window, "location");

function stubSdk(login: FacebookSdk["login"]): void {
  window.FB = { init: vi.fn(), login: vi.fn(login) };
}

beforeEach(async () => {
  vi.resetModules();
  mod = await import("../facebook");
  Object.defineProperty(window, "location", {
    value: { protocol: "https:" },
    configurable: true,
  });
  delete window.FB;
  delete window.fbAsyncInit;
  document.getElementById("facebook-jssdk")?.remove();
});

afterEach(() => {
  if (originalOpen) Object.defineProperty(window, "open", originalOpen);
  else delete (window as { open?: unknown }).open;
  if (originalLocation) Object.defineProperty(window, "location", originalLocation);
  else delete (window as { location?: unknown }).location;
  delete window.FB;
  delete window.fbAsyncInit;
  document.getElementById("facebook-jssdk")?.remove();
});

describe("isFacebookInAppBrowser", () => {
  it("detects the Facebook and Instagram in-app browsers", () => {
    expect(
      isFacebookInAppBrowser(
        "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) Mobile/15E148 [FBAN/FBAV;]",
      ),
    ).toBe(true);
    expect(
      isFacebookInAppBrowser(
        "Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 Instagram 300.0",
      ),
    ).toBe(true);
    expect(isFacebookInAppBrowser("Mozilla/5.0 (Macintosh) Chrome/120.0")).toBe(
      false,
    );
    expect(isFacebookInAppBrowser(undefined)).toBe(false);
  });
});

describe("facebookRedirectUri", () => {
  it("points at the locale-independent callback", () => {
    expect(facebookRedirectUri("https://shop.example")).toBe(
      "https://shop.example/fb-callback",
    );
  });
});

describe("loadFacebookSdk", () => {
  it("resolves and inits an SDK that is already on the page", async () => {
    window.FB = { init: vi.fn(), login: vi.fn() };

    const sdk = await mod.loadFacebookSdk("app-1");

    expect(sdk).toBe(window.FB);
    expect(window.FB?.init).toHaveBeenCalledWith(
      expect.objectContaining({ appId: "app-1", version: "v20.0" }),
    );
  });

  it("injects the SDK script exactly once", async () => {
    const promise = mod.loadFacebookSdk("app-1");

    expect(
      document.querySelectorAll(
        'script#facebook-jssdk[src*="connect.facebook.net"]',
      ),
    ).toHaveLength(1);

    // A second call before the script loads reuses the same promise.
    expect(mod.loadFacebookSdk("app-1")).toBe(promise);

    // Resolve the pending promise so the test does not leak state.
    window.FB = { init: vi.fn(), login: vi.fn() };
    window.fbAsyncInit?.();
    await expect(promise).resolves.toBeTruthy();
  });

  it("rejects when the script fails to load", async () => {
    const promise = mod.loadFacebookSdk("app-1");

    document
      .getElementById("facebook-jssdk")
      ?.dispatchEvent(new Event("error"));

    await expect(promise).rejects.toThrow();
  });
});

describe("facebookPopupLogin", () => {
  it("resolves with the access token from FB.login", async () => {
    stubSdk((callback) =>
      callback({ authResponse: { accessToken: "fb-token" } }),
    );

    await expect(mod.facebookPopupLogin("app-1")).resolves.toEqual({
      token: "fb-token",
    });
  });

  it("reports a dismissed dialog as cancelled", async () => {
    stubSdk((callback) => callback({ authResponse: null }));

    await expect(mod.facebookPopupLogin("app-1")).resolves.toBe("cancelled");
  });

  it("uses the SDK popup directly without opening a probe window", async () => {
    const open = vi.spyOn(window, "open");
    stubSdk((callback) => callback({ authResponse: { accessToken: "t" } }));

    await expect(mod.facebookPopupLogin("app-1")).resolves.toEqual({
      token: "t",
    });
    expect(open).not.toHaveBeenCalled();
  });

  it("does not call FB.login on an HTTP page", async () => {
    Object.defineProperty(window, "location", {
      value: { protocol: "http:" },
      configurable: true,
    });
    const login = vi.fn();
    stubSdk(login);

    await expect(mod.facebookPopupLogin("app-1")).resolves.toBe("unavailable");
    expect(login).not.toHaveBeenCalled();
  });

  it("falls back when the SDK cannot load", async () => {
    // No window.FB and the injected script never fires fbAsyncInit — the
    // load promise stays pending, so drive rejection through onerror.
    const promise = mod.facebookPopupLogin("app-1");
    document
      .getElementById("facebook-jssdk")
      ?.dispatchEvent(new Event("error"));

    await expect(promise).resolves.toBe("unavailable");
  });
});
