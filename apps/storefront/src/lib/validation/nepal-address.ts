import { z } from "zod";

/**
 * Nepali phone rules — shared with the backend
 * (`backend/app/models/spree/address_decorator.rb`).
 *
 * The backend strips spaces and dashes, then matches one of:
 * - mobile: optional +977 prefix + 97/98 + 8 digits
 * - landline: optional +977 prefix + optional trunk 0 + 8-9 digits
 *
 * The two regexes below are the SAME rules in JS syntax. Keep them in sync
 * with `NEPALI_MOBILE_RE` / `NEPALI_LANDLINE_RE` on the backend.
 */
export const NEPALI_MOBILE_RE = /^(\+977)?(97|98)\d{8}$/;
export const NEPALI_LANDLINE_RE = /^(\+977)?0?\d{8,9}$/;

/** Strip spaces and dashes the same way the backend does before matching. */
export function normalizeNepaliPhone(phone: string): string {
  return phone.replace(/[ \-\u2013\u2014]/g, "");
}

/**
 * Accept a bare `977` country prefix (without the `+`) and normalize it to
 * the `+977` form the backend expects — the backend regex only allows an
 * optional `+977`, so `9779841234567` would otherwise fail server-side.
 */
export function canonicalizeNepaliPhone(phone: string): string {
  const normalized = normalizeNepaliPhone(phone.trim());
  if (/^977\d+$/.test(normalized)) {
    return `+${normalized}`;
  }
  return normalized;
}

export function isValidNepaliPhone(phone: string): boolean {
  const normalized = canonicalizeNepaliPhone(phone);
  return (
    NEPALI_MOBILE_RE.test(normalized) || NEPALI_LANDLINE_RE.test(normalized)
  );
}

/**
 * Split a full name the way the backend expects firstname + lastname.
 * Single names are duplicated into both fields so the backend presence
 * validations pass (common for Nepali single names).
 */
export function splitFullName(fullName: string): {
  first_name: string;
  last_name: string;
} {
  const parts = fullName.trim().split(/\s+/).filter(Boolean);
  const first_name = parts[0] ?? "";
  const last_name = parts.length > 1 ? parts.slice(1).join(" ") : first_name;
  return { first_name, last_name };
}

export function joinFullName(
  firstName: string | null,
  lastName: string | null,
): string {
  return [firstName, lastName]
    .map((p) => p?.trim() ?? "")
    .filter(Boolean)
    .join(" ");
}

const phoneSchema = z
  .string()
  .trim()
  .min(1, "phoneRequired")
  .refine((value) => isValidNepaliPhone(value), "phoneInvalid");

/**
 * Nepal checkout address form values. Error strings are message keys —
 * components resolve them with `t(key)` so every locale renders properly.
 */
export const nepalAddressSchema = z.object({
  fullName: z.string().trim().min(2, "fullNameRequired"),
  phone: phoneSchema.transform((value) =>
    canonicalizeNepaliPhone(value.trim()),
  ),
  provinceId: z.string().min(1, "provinceRequired"),
  districtId: z.string().min(1, "districtRequired"),
  address1: z.string().trim().min(1, "streetRequired"),
  city: z.string().trim().min(1, "cityRequired"),
  postalCode: z.string().trim().optional().default(""),
});

export type NepalAddressFormValues = z.input<typeof nepalAddressSchema>;
export type NepalAddressData = z.output<typeof nepalAddressSchema>;
