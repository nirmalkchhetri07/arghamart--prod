import { describe, expect, it } from "vitest";
import {
  canonicalizeNepaliPhone,
  isValidNepaliPhone,
  joinFullName,
  NEPALI_LANDLINE_RE,
  NEPALI_MOBILE_RE,
  nepalAddressSchema,
  normalizeNepaliPhone,
  splitFullName,
} from "../nepal-address";

describe("Nepali phone regexes (mirror backend address_decorator.rb)", () => {
  it("matches the backend mobile rule", () => {
    expect(NEPALI_MOBILE_RE.source).toBe(/^(\+977)?(97|98)\d{8}$/.source);
    for (const phone of ["9841234567", "9741234567", "+9779841234567"]) {
      expect(NEPALI_MOBILE_RE.test(phone)).toBe(true);
    }
    for (const phone of ["984123456", "9641234567", "9779841234567"]) {
      expect(NEPALI_MOBILE_RE.test(phone)).toBe(false);
    }
  });

  it("matches the backend landline rule", () => {
    expect(NEPALI_LANDLINE_RE.source).toBe(/^(\+977)?0?\d{8,9}$/.source);
    for (const phone of ["014412345", "14412345", "+97714412345"]) {
      expect(NEPALI_LANDLINE_RE.test(phone)).toBe(true);
    }
  });
});

describe("normalizeNepaliPhone", () => {
  it("strips spaces and dashes like the backend", () => {
    expect(normalizeNepaliPhone("984-123-4567")).toBe("9841234567");
    expect(normalizeNepaliPhone("+977 9841234567")).toBe("+9779841234567");
  });
});

describe("canonicalizeNepaliPhone", () => {
  it("rewrites a bare 977 prefix to +977 (backend only allows +977)", () => {
    expect(canonicalizeNepaliPhone("9779841234567")).toBe("+9779841234567");
    expect(canonicalizeNepaliPhone("+9779841234567")).toBe("+9779841234567");
    expect(canonicalizeNepaliPhone("9841234567")).toBe("9841234567");
  });
});

describe("isValidNepaliPhone", () => {
  it("accepts mobiles with optional +977/977 prefix", () => {
    for (const phone of [
      "9841234567",
      "9741234567",
      "+9779841234567",
      "9779841234567",
      "984-123-4567",
      "+977-9841234567",
    ]) {
      expect(isValidNepaliPhone(phone)).toBe(true);
    }
  });

  it("accepts common landlines", () => {
    for (const phone of ["01-4412345", "014412345", "+9771-4412345"]) {
      expect(isValidNepaliPhone(phone)).toBe(true);
    }
  });

  it("rejects non-Nepali numbers", () => {
    // NOTE: "98412345" (8 digits) matches the permissive landline rule
    // shared with the backend — Spree's Phonelib validator rejects it
    // server-side for NP. These fail even the shared rule:
    for (const phone of [
      "123",
      "9841234",
      "abcdefghij",
      "+1-555-123-4567",
      "",
    ]) {
      expect(isValidNepaliPhone(phone)).toBe(false);
    }
  });
});

describe("splitFullName / joinFullName", () => {
  it("splits on the first space", () => {
    expect(splitFullName("Asha Shrestha")).toEqual({
      first_name: "Asha",
      last_name: "Shrestha",
    });
    expect(splitFullName("Asha Devi Shrestha")).toEqual({
      first_name: "Asha",
      last_name: "Devi Shrestha",
    });
  });

  it("duplicates single names so backend presence passes", () => {
    expect(splitFullName("Asha")).toEqual({
      first_name: "Asha",
      last_name: "Asha",
    });
  });

  it("round-trips", () => {
    expect(joinFullName("Asha", "Shrestha")).toBe("Asha Shrestha");
    expect(joinFullName(null, null)).toBe("");
  });
});

describe("nepalAddressSchema", () => {
  const valid = {
    fullName: "Asha Shrestha",
    phone: "9841234567",
    provinceId: "prov_1",
    districtId: "dist_1",
    address1: "Thamel 123",
    city: "Kathmandu",
    postalCode: "",
  };

  it("accepts a complete address and canonicalizes the phone", () => {
    const parsed = nepalAddressSchema.parse({
      ...valid,
      phone: "9779841234567",
    });
    expect(parsed.phone).toBe("+9779841234567");
  });

  it("rejects short names, bad phones, and missing province/district", () => {
    expect(() =>
      nepalAddressSchema.parse({ ...valid, fullName: "A" }),
    ).toThrow();
    expect(() =>
      nepalAddressSchema.parse({ ...valid, phone: "123" }),
    ).toThrow();
    expect(() =>
      nepalAddressSchema.parse({ ...valid, provinceId: "" }),
    ).toThrow();
    expect(() =>
      nepalAddressSchema.parse({ ...valid, districtId: "" }),
    ).toThrow();
    expect(() =>
      nepalAddressSchema.parse({ ...valid, address1: "", city: "" }),
    ).toThrow();
  });

  it("keeps zip optional", () => {
    const parsed = nepalAddressSchema.parse({ ...valid, postalCode: "44600" });
    expect(parsed.postalCode).toBe("44600");
  });
});
