import { describe, expect, it } from "vitest";
import { emptyAddress, updateAddressField } from "../address";

describe("updateAddressField (Nepal cascading clears)", () => {
  it("clears district and city when the province changes", () => {
    const updated = updateAddressField(
      {
        ...emptyAddress,
        province_id: "prov_old",
        district_id: "dist_old",
        city: "Biratnagar",
      },
      "province_id",
      "prov_new",
    );
    expect(updated.district_id).toBe("");
    expect(updated.city).toBe("");
  });

  it("clears the municipality when the district changes", () => {
    const updated = updateAddressField(
      { ...emptyAddress, district_id: "dist_old", city: "Biratnagar" },
      "district_id",
      "dist_new",
    );
    expect(updated.district_id).toBe("dist_new");
    expect(updated.city).toBe("");
  });

  it("leaves the city untouched for unrelated fields", () => {
    const updated = updateAddressField(
      { ...emptyAddress, city: "Biratnagar" },
      "address1",
      "Main Road 1",
    );
    expect(updated.city).toBe("Biratnagar");
  });
});
