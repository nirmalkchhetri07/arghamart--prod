import { describe, expect, it } from "vitest";
import {
  DEFAULT_LOCALE,
  loadMessages,
  resolveSupportedLocale,
  SUPPORTED_LOCALES,
} from "@/i18n/locales";
import {
  canonicalizeLocale,
  matchLocale,
  negotiateAcceptLanguage,
  negotiateLocale,
} from "@/i18n/normalize";

describe("locale configuration", () => {
  it("resolves configured locales case-insensitively", () => {
    expect(resolveSupportedLocale("EN")).toBe("en");
    expect(resolveSupportedLocale("it")).toBeUndefined();
    expect(SUPPORTED_LOCALES).toContain(DEFAULT_LOCALE);
  });

  it("supports Nepali (ne) for the Nepal market", () => {
    expect(SUPPORTED_LOCALES).toContain("ne");
    expect(resolveSupportedLocale("ne")).toBe("ne");
    expect(resolveSupportedLocale("NE")).toBe("ne");
  });

  it("loads the Nepali message bundle with full key parity", async () => {
    const [en, ne] = await Promise.all([
      loadMessages("en"),
      loadMessages("ne"),
    ]);
    const flatten = (obj: Record<string, unknown>, prefix = ""): string[] =>
      Object.entries(obj).flatMap(([key, value]) =>
        value && typeof value === "object"
          ? flatten(value as Record<string, unknown>, `${prefix}${key}.`)
          : [`${prefix}${key}`],
      );
    const enKeys = new Set(flatten(en as Record<string, unknown>));
    const neMessages = ne as Record<string, unknown>;
    for (const key of enKeys) {
      const parts = key.split(".");
      let node: unknown = neMessages;
      for (const part of parts) {
        node =
          node && typeof node === "object"
            ? (node as Record<string, unknown>)[part]
            : undefined;
      }
      expect(node, `ne.json missing key: ${key}`).not.toBeUndefined();
    }
    const checkout = (
      (neMessages as { checkout?: unknown }).checkout ?? {}
    ) as { esewaRedirectTitle?: unknown; khaltiRedirectTitle?: unknown };
    expect(checkout.esewaRedirectTitle).toBeTruthy();
    expect(checkout.khaltiRedirectTitle).toBeTruthy();
  });

  it("canonicalizes BCP 47 and Rails-style locale codes", () => {
    expect(canonicalizeLocale("zh_cn")).toBe("zh-CN");
    expect(canonicalizeLocale("sr_latn_rs")).toBe("sr-Latn-RS");
    expect(canonicalizeLocale("not_a_locale_!")).toBeUndefined();
  });

  it("preserves configured spelling and negotiates a base language", () => {
    const supported = ["en", "zh-CN"] as const;
    expect(matchLocale("zh-cn", supported)).toBe("zh-CN");
    expect(negotiateLocale("en-US", supported)).toBe("en");
  });

  it("honors Accept-Language quality weights and rejects q=0 entries", () => {
    const supported = ["en", "de"] as const;

    expect(negotiateAcceptLanguage("de;q=0.2, en-US;q=0.9", supported)).toBe(
      "en",
    );
    expect(negotiateAcceptLanguage("de;q=0, en;q=0.5", supported)).toBe("en");
  });
});
