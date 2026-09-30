"use client";

import type { Country, State } from "@spree/sdk";
import { useTranslations } from "next-intl";
import type { Ref } from "react";
import {
  NepalAddressForm,
  type NepalAddressFormHandle,
} from "@/components/checkout/NepalAddressForm";
import { Input } from "@/components/ui/input";
import {
  NativeSelect,
  NativeSelectOption,
} from "@/components/ui/native-select";
import type { NepalProvince } from "@/lib/data/nepal";
import { type AddressFormData, addressFullName } from "@/lib/utils/address";
import {
  type NepalAddressFormValues,
  splitFullName,
} from "@/lib/validation/nepal-address";

interface AddressFormFieldsProps {
  address: AddressFormData;
  countries: Country[];
  states: State[];
  loadingStates: boolean;
  onChange: (field: keyof AddressFormData, value: string) => void;
  idPrefix: string;
  /**
   * When provided, the generic country/state fields are replaced by the
   * Nepal-specific form (fixed NP country, province + district comboboxes,
   * react-hook-form + zod validation). Billing and other generic flows omit
   * this and keep the classic fields.
   */
  nepalProvinces?: NepalProvince[];
  loadingNepalProvinces?: boolean;
  nepalFormRef?: Ref<NepalAddressFormHandle>;
  onNepalBlur?: () => void;
}

export function AddressFormFields({
  address,
  countries,
  states,
  loadingStates,
  onChange,
  idPrefix,
  nepalProvinces,
  loadingNepalProvinces,
  nepalFormRef,
  onNepalBlur,
}: AddressFormFieldsProps) {
  const t = useTranslations("address");
  const tc = useTranslations("common");

  if (nepalProvinces) {
    const handleNepalChange = (values: NepalAddressFormValues) => {
      // Bridge RHF values into the controlled AddressFormData fields the
      // parent autosave machinery works with.
      const { first_name, last_name } = splitFullName(values.fullName);
      const mapping: [keyof AddressFormData, string][] = [
        ["first_name", first_name],
        ["last_name", last_name],
        ["phone", values.phone],
        ["province_id", values.provinceId],
        ["district_id", values.districtId],
        ["address1", values.address1],
        ["city", values.city],
        ["postal_code", values.postalCode ?? ""],
        ["country_iso", "NP"],
      ];
      for (const [field, value] of mapping) {
        if (address[field] !== value) onChange(field, value);
      }
    };

    return (
      <NepalAddressForm
        ref={nepalFormRef}
        provinces={nepalProvinces}
        loadingProvinces={loadingNepalProvinces}
        defaultValues={{
          fullName: addressFullName(address),
          phone: address.phone,
          provinceId: address.province_id,
          districtId: address.district_id,
          address1: address.address1,
          city: address.city,
          postalCode: address.postal_code,
        }}
        onChange={handleNepalChange}
        onFieldBlur={onNepalBlur}
        idPrefix={idPrefix}
      />
    );
  }

  const hasStates = states.length > 0;

  return (
    <div className="flex flex-col gap-3">
      {/* Country — full width, floating label style */}
      <div className="relative">
        <NativeSelect
          id={`${idPrefix}-country`}
          aria-label={t("country")}
          className="w-full"
          value={address.country_iso}
          onChange={(e) => onChange("country_iso", e.target.value)}
          required
        >
          <NativeSelectOption value="" disabled>
            {t("selectCountry")}
          </NativeSelectOption>
          {countries.map((country) => (
            <NativeSelectOption key={country.iso} value={country.iso}>
              {country.name}
            </NativeSelectOption>
          ))}
        </NativeSelect>
      </div>

      {/* First name / Last name */}
      <div className="grid grid-cols-2 gap-3">
        <Input
          type="text"
          id={`${idPrefix}-first_name`}
          aria-label={t("firstName")}
          value={address.first_name}
          onChange={(e) => onChange("first_name", e.target.value)}
          placeholder={t("firstName")}
        />
        <Input
          type="text"
          id={`${idPrefix}-last_name`}
          aria-label={t("lastName")}
          required
          value={address.last_name}
          onChange={(e) => onChange("last_name", e.target.value)}
          placeholder={t("lastName")}
        />
      </div>

      {/* Company */}
      <Input
        type="text"
        id={`${idPrefix}-company`}
        aria-label={t("company")}
        value={address.company}
        onChange={(e) => onChange("company", e.target.value)}
        placeholder={t("company")}
      />

      {/* Address */}
      <Input
        type="text"
        id={`${idPrefix}-address1`}
        aria-label={t("address")}
        required
        value={address.address1}
        onChange={(e) => onChange("address1", e.target.value)}
        placeholder={t("address")}
      />

      {/* Apartment */}
      <Input
        type="text"
        id={`${idPrefix}-address2`}
        aria-label={t("apartment")}
        value={address.address2}
        onChange={(e) => onChange("address2", e.target.value)}
        placeholder={t("apartment")}
      />

      {/* City / State / ZIP — 3 columns */}
      <div className="grid grid-cols-3 gap-3">
        <Input
          type="text"
          id={`${idPrefix}-city`}
          aria-label={t("city")}
          required
          value={address.city}
          onChange={(e) => onChange("city", e.target.value)}
          placeholder={t("city")}
        />
        {loadingStates ? (
          <NativeSelect
            id={`${idPrefix}-state`}
            aria-label={t("stateProvince")}
            className="w-full"
            disabled
          >
            <NativeSelectOption value="">{tc("loading")}</NativeSelectOption>
          </NativeSelect>
        ) : hasStates ? (
          <NativeSelect
            id={`${idPrefix}-state`}
            aria-label={t("stateProvince")}
            className="w-full"
            value={address.state_abbr}
            onChange={(e) => onChange("state_abbr", e.target.value)}
            required
          >
            <NativeSelectOption value="" disabled>
              {t("selectState")}
            </NativeSelectOption>
            {states.map((state) => (
              <NativeSelectOption key={state.abbr} value={state.abbr}>
                {state.name}
              </NativeSelectOption>
            ))}
          </NativeSelect>
        ) : (
          <Input
            type="text"
            id={`${idPrefix}-state`}
            aria-label={t("stateProvince")}
            value={address.state_name}
            onChange={(e) => onChange("state_name", e.target.value)}
            placeholder={t("stateProvince")}
          />
        )}
        <Input
          type="text"
          id={`${idPrefix}-postal_code`}
          aria-label={t("zipCode")}
          required
          value={address.postal_code}
          onChange={(e) => onChange("postal_code", e.target.value)}
          placeholder={t("zipCode")}
        />
      </div>

      {/* Phone — required: eSewa/Khalti need it at payment time */}
      <Input
        type="tel"
        id={`${idPrefix}-phone`}
        aria-label={t("phone")}
        required
        value={address.phone}
        onChange={(e) => onChange("phone", e.target.value)}
        placeholder={t("phone")}
      />
    </div>
  );
}
