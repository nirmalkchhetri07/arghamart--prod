import type { Address, AddressParams } from "@spree/sdk";
import { joinFullName, splitFullName } from "@/lib/validation/nepal-address";

/**
 * Backend-provided Nepal fields on addresses (see
 * `backend/app/serializers/spree/api/v3/address_serializer_decorator.rb`).
 * The SDK types don't know them yet, so reads cast through this.
 */
export interface NepalAddressFields {
  province_id?: string | null;
  district_id?: string | null;
  province_name?: string | null;
  district_name?: string | null;
  district_shipping_fee?: string | null;
}

export type NepalAddress = Address & NepalAddressFields;

/** Write params for Nepal addresses — SDK type plus the new backend fields. */
export type NepalAddressParams = AddressParams & {
  province_id?: string;
  district_id?: string;
  province_name?: string;
  district_name?: string;
};

export interface AddressFormData {
  first_name: string;
  last_name: string;
  address1: string;
  address2: string;
  city: string;
  postal_code: string;
  phone: string;
  company: string;
  country_iso: string;
  state_abbr: string;
  state_name: string;
  province_id: string;
  district_id: string;
}

export const emptyAddress: AddressFormData = {
  first_name: "",
  last_name: "",
  address1: "",
  address2: "",
  city: "",
  postal_code: "",
  phone: "",
  company: "",
  country_iso: "",
  state_abbr: "",
  state_name: "",
  province_id: "",
  district_id: "",
};

type AddressLike = {
  first_name: string | null;
  last_name: string | null;
  address1: string | null;
  address2: string | null;
  city: string | null;
  postal_code: string | null;
  phone: string | null;
  company: string | null;
  country_iso: string;
  state_abbr: string | null;
  state_name: string | null;
} & Partial<NepalAddressFields>;

export function addressToFormData(
  address?: AddressLike | null,
): AddressFormData {
  if (!address) return { ...emptyAddress };
  return {
    first_name: address.first_name || "",
    last_name: address.last_name || "",
    address1: address.address1 || "",
    address2: address.address2 || "",
    city: address.city || "",
    postal_code: address.postal_code || "",
    phone: address.phone || "",
    company: address.company || "",
    country_iso: address.country_iso || "",
    state_abbr: address.state_abbr || "",
    state_name: address.state_name || "",
    province_id: address.province_id || "",
    district_id: address.district_id || "",
  };
}

export function formDataToAddress(data: AddressFormData): NepalAddressParams {
  const params: NepalAddressParams = {
    first_name: data.first_name,
    last_name: data.last_name,
    address1: data.address1,
    address2: data.address2 || undefined,
    city: data.city,
    postal_code: data.postal_code,
    phone: data.phone || undefined,
    company: data.company || undefined,
    country_iso: data.country_iso,
    state_abbr: data.state_abbr || undefined,
    state_name: data.state_name || undefined,
  };
  if (data.province_id) params.province_id = data.province_id;
  if (data.district_id) params.district_id = data.district_id;
  // Nepal addresses always ship within NP — the Nepal form fixes the
  // country, so force it here even if the form state predates that.
  if (data.province_id || data.district_id) {
    params.country_iso = "NP";
  }
  return params;
}

/** True when a saved address still needs a district (legacy addresses). */
export function addressNeedsDistrict(
  address: AddressLike | null | undefined,
): boolean {
  if (!address) return false;
  return !(address.province_id && address.district_id);
}

export function addressFullName(
  address: AddressLike | null | undefined,
): string {
  if (!address) return "";
  return joinFullName(address.first_name, address.last_name);
}

/** Merge Nepal-form values into AddressFormData (full name is split). */
export function applyNepalValues(
  prev: AddressFormData,
  values: {
    fullName: string;
    phone: string;
    provinceId: string;
    districtId: string;
    address1: string;
    city: string;
    postalCode: string;
  },
): AddressFormData {
  const { first_name, last_name } = splitFullName(values.fullName);
  return {
    ...prev,
    first_name,
    last_name,
    phone: values.phone,
    province_id: values.provinceId,
    district_id: values.districtId,
    address1: values.address1,
    city: values.city,
    postal_code: values.postalCode ?? "",
    country_iso: "NP",
  };
}

/**
 * Returns an updated address with the given field changed.
 * Clears state fields when country changes, clears the district when the
 * province changes (it belongs to the old province), and clears the city /
 * municipality when the district changes (it belongs to the old district).
 */
export function updateAddressField(
  address: AddressFormData,
  field: keyof AddressFormData,
  value: string,
): AddressFormData {
  const updated = { ...address, [field]: value };
  if (field === "country_iso") {
    updated.state_abbr = "";
    updated.state_name = "";
  }
  if (field === "province_id") {
    updated.district_id = "";
    updated.city = "";
  }
  if (field === "district_id") {
    updated.city = "";
  }
  return updated;
}
