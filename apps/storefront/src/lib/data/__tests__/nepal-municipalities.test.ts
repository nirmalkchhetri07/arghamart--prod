import { describe, expect, it } from "vitest";
import {
  formatMunicipalityOption,
  getMunicipalitiesForDistrict,
  municipalityDistrictCount,
} from "../nepal-municipalities";

describe("getMunicipalitiesForDistrict", () => {
  it("covers all 77 districts", () => {
    expect(municipalityDistrictCount()).toBe(77);
  });

  it("returns Morang's local levels with Biratnagar first", () => {
    const levels = getMunicipalitiesForDistrict("Morang");
    expect(levels).toHaveLength(17);
    expect(levels[0]).toMatchObject({
      name_en: "Biratnagar",
      type_en: "Metropolitan City",
    });
  });

  it("returns Arghakhanchi's 6 local levels", () => {
    const names = getMunicipalitiesForDistrict("Arghakhanchi").map(
      (l) => l.name_en,
    );
    expect(names).toEqual([
      "Bhumekasthan",
      "Sitganga",
      "Sandhikharka",
      "Panini",
      "Chhatradev",
      "Malarani",
    ]);
  });

  it("returns Gulmi's 12 local levels including Dhurkot", () => {
    const names = getMunicipalitiesForDistrict("Gulmi").map((l) => l.name_en);
    expect(names).toHaveLength(12);
    expect(names).toContain("Dhurkot");
  });

  it("resolves backend spellings that differ from the source dataset", () => {
    // Backend Panchthar ↔ source Pachthar
    expect(
      getMunicipalitiesForDistrict("Panchthar").map((l) => l.name_en),
    ).toContain("Phidim");
    // Backend Tanahun ↔ source Tanahu
    expect(
      getMunicipalitiesForDistrict("Tanahun").map((l) => l.name_en),
    ).toContain("Byas");
    // Backend Nawalpur ↔ source Nawalparasi East (plus the legacy
    // "Nawalparari East" typo from an earlier revision of this dataset)
    expect(
      getMunicipalitiesForDistrict("Nawalpur").map((l) => l.name_en),
    ).toContain("Kawasoti");
    expect(
      getMunicipalitiesForDistrict("Nawalparasi East").map((l) => l.name_en),
    ).toContain("Kawasoti");
    expect(
      getMunicipalitiesForDistrict("Nawalparari East").map((l) => l.name_en),
    ).toContain("Kawasoti");
    // Backend Parasi ↔ source Nawalparasi West
    expect(
      getMunicipalitiesForDistrict("Parasi").map((l) => l.name_en),
    ).toContain("Ramgram");
    // Backend Kapilvastu ↔ source Kapilbastu
    expect(
      getMunicipalitiesForDistrict("Kapilvastu").map((l) => l.name_en),
    ).toContain("Banganga");
  });

  it("is case-insensitive and ignores separators", () => {
    expect(getMunicipalitiesForDistrict("rukum east")).toHaveLength(3);
    expect(getMunicipalitiesForDistrict("  KATHMANDU ")).toHaveLength(11);
  });

  it("returns [] for blank or unknown districts (checkout falls back to free text)", () => {
    expect(getMunicipalitiesForDistrict("")).toEqual([]);
    expect(getMunicipalitiesForDistrict(null)).toEqual([]);
    expect(getMunicipalitiesForDistrict(undefined)).toEqual([]);
    expect(getMunicipalitiesForDistrict("Atlantis")).toEqual([]);
  });
});

describe("formatMunicipalityOption", () => {
  const biratnagar = {
    name_en: "Biratnagar",
    name_ne: "विराटनगर",
    type_en: "Metropolitan City",
    type_ne: "महानगरपालिका",
  };

  it("leads with English outside the Nepali locale", () => {
    expect(formatMunicipalityOption(biratnagar, "en")).toBe(
      "Biratnagar (Metropolitan City) · विराटनगर",
    );
    expect(formatMunicipalityOption(biratnagar)).toBe(
      "Biratnagar (Metropolitan City) · विराटनगर",
    );
  });

  it("leads with Nepali in the Nepali locale", () => {
    expect(formatMunicipalityOption(biratnagar, "ne")).toBe(
      "विराटनगर (महानगरपालिका) · Biratnagar",
    );
  });
});
