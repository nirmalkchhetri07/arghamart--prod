import { describe, expect, it } from "vitest";
import {
  buildFacebookAuthorizeUrl,
  buildGithubAuthorizeUrl,
  createOauthState,
  FB_CALLBACK_PATH,
  isOauthCodeProvider,
  isPendingOauthCode,
  oauthReturnToKey,
  oauthStateKey,
  parseOauthState,
} from "../oauth-client";

const PARAMS = {
  clientId: "test-client-id",
  redirectUri: "https://shop.example/fb-callback",
  state: "opaque-state",
};

describe("oauth-client", () => {
  it("treats only GitHub as a redirect-code provider", () => {
    expect(isOauthCodeProvider("github")).toBe(true);
    // Facebook moved to the SDK/token flow with a fixed /fb-callback page.
    expect(isOauthCodeProvider("facebook")).toBe(false);
    expect(isOauthCodeProvider("google")).toBe(false);
    expect(isOauthCodeProvider("myspace")).toBe(false);
  });

  it("exposes the fixed Facebook callback path", () => {
    expect(FB_CALLBACK_PATH).toBe("/fb-callback");
  });

  it("builds the Facebook token-flow authorize URL", () => {
    const url = new URL(buildFacebookAuthorizeUrl(PARAMS));

    expect(`${url.origin}${url.pathname}`).toBe(
      "https://www.facebook.com/v20.0/dialog/oauth",
    );
    expect(url.searchParams.get("client_id")).toBe("test-client-id");
    expect(url.searchParams.get("redirect_uri")).toBe(PARAMS.redirectUri);
    expect(url.searchParams.get("response_type")).toBe("token");
    expect(url.searchParams.get("scope")).toContain("email");
    expect(url.searchParams.get("state")).toBe("opaque-state");
  });

  it("builds the GitHub authorize URL", () => {
    const url = new URL(
      buildGithubAuthorizeUrl({
        ...PARAMS,
        redirectUri: "https://shop.example/us/en/auth/callback/github",
      }),
    );

    expect(`${url.origin}${url.pathname}`).toBe(
      "https://github.com/login/oauth/authorize",
    );
    expect(url.searchParams.get("client_id")).toBe("test-client-id");
    expect(url.searchParams.get("scope")).toBe("user:email");
    expect(url.searchParams.get("state")).toBe("opaque-state");
  });

  it("round-trips state with a unique nonce per flow", () => {
    const first = createOauthState("/us/en/account");
    const second = createOauthState("/us/en/account");

    expect(first.nonce).not.toBe(second.nonce);
    expect(parseOauthState(first.state)).toEqual({
      next: "/us/en/account",
      nonce: first.nonce,
    });
    expect(parseOauthState(second.state)?.nonce).toBe(second.nonce);
  });

  it("supports flows without a return target", () => {
    const { state, nonce } = createOauthState(null);

    expect(parseOauthState(state)).toEqual({ next: null, nonce });
  });

  it("rejects malformed state values", () => {
    expect(parseOauthState(null)).toBeNull();
    expect(parseOauthState("")).toBeNull();
    expect(parseOauthState("not-base64!!!")).toBeNull();
    expect(parseOauthState(btoa("just a string"))).toBeNull();
  });

  it("scopes the storage keys per provider", () => {
    expect(oauthStateKey("facebook")).toBe("oauth:state:facebook");
    expect(oauthStateKey("github")).not.toBe(oauthStateKey("facebook"));
    expect(oauthReturnToKey("facebook")).toBe("oauth:returnTo:facebook");
    expect(oauthReturnToKey("github")).not.toBe(oauthReturnToKey("facebook"));
  });

  it("identifies the two pending-completion codes", () => {
    expect(isPendingOauthCode("email_missing")).toBe(true);
    expect(isPendingOauthCode("account_exists_confirm_required")).toBe(true);
    expect(isPendingOauthCode("invalid_token")).toBe(false);
    expect(isPendingOauthCode(undefined)).toBe(false);
  });
});
