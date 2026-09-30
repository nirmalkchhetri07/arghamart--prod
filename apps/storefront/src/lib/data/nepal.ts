"use server";

import { getConfig } from "@/lib/spree";
import { withFallback } from "./utils";

export interface NepalDistrict {
  id: string;
  name: string;
}

export interface NepalProvince {
  id: string;
  name: string;
  code: string;
  districts: NepalDistrict[];
}

/**
 * Typed fetcher for the Nepal province/district reference data — the ONLY
 * source of truth for the checkout dropdowns. Reads live from
 * `GET /api/v3/store/nepal/provinces` (active districts only), never from a
 * hardcoded list, so districts added or deactivated in /admin/manage-address
 * take effect. Cached for an hour; admin changes are rare.
 */
export async function getNepalProvinces(): Promise<{ data: NepalProvince[] }> {
  return withFallback(
    async () => {
      const config = getConfig();
      const response = await fetch(
        `${config.baseUrl.replace(/\/$/, "")}/api/v3/store/nepal/provinces`,
        {
          headers: { "x-spree-api-key": config.publishableKey },
          next: { revalidate: 3600, tags: ["nepal-provinces"] },
        },
      );
      if (!response.ok) {
        throw new Error(`Failed to load provinces (${response.status})`);
      }
      return (await response.json()) as { data: NepalProvince[] };
    },
    { data: [] },
  );
}
