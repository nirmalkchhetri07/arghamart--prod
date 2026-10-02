import { beforeEach, describe, expect, it, vi } from "vitest";

const { getProductFromApi, cacheLife, cacheTag } = vi.hoisted(() => ({
  getProductFromApi: vi.fn(),
  cacheLife: vi.fn(),
  cacheTag: vi.fn(),
}));

vi.mock("@/lib/spree", () => ({
  cacheTagSuffix: (surface: string) => (surface === "dtc" ? "" : `-${surface}`),
  DEFAULT_SURFACE: "dtc",
  getAccessToken: vi.fn().mockResolvedValue(undefined),
  getClientForSurface: vi.fn(() => ({
    products: { get: getProductFromApi },
  })),
  getLocaleOptions: vi.fn().mockResolvedValue({ country: "us", locale: "en" }),
}));

vi.mock("next/cache", () => ({
  cacheLife,
  cacheTag,
}));

import { getProduct } from "@/lib/data/products";

describe("getProduct", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("fetches current product data directly from the Store API", async () => {
    const product = { id: "product-1", in_stock: true };
    getProductFromApi.mockResolvedValue(product);

    await expect(
      getProduct("induction-cooker", { expand: ["default_variant"] }),
    ).resolves.toBe(product);

    expect(getProductFromApi).toHaveBeenCalledWith(
      "induction-cooker",
      { expand: ["default_variant"] },
      { country: "us", locale: "en" },
    );
    expect(cacheLife).not.toHaveBeenCalled();
    expect(cacheTag).not.toHaveBeenCalled();
  });
});
