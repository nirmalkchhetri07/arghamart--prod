"use client";

import type { Address, AddressParams, Cart, Country, State } from "@spree/sdk";
import { Loader2 } from "lucide-react";
import Link from "next/link";
import { useTranslations } from "next-intl";
import { useCallback, useEffect, useRef, useState } from "react";
import { AddressEditModal } from "@/components/checkout/AddressEditModal";
import { AddressFormFields } from "@/components/checkout/AddressFormFields";
import { AddressSelector } from "@/components/checkout/AddressSelector";
import type { NepalAddressFormHandle } from "@/components/checkout/NepalAddressForm";
import { Input } from "@/components/ui/input";
import type { User } from "@/contexts/AuthContext";
import { useCountryStates } from "@/hooks/useCountryStates";
import type { NepalProvince } from "@/lib/data/nepal";
import {
  type AddressFormData,
  addressNeedsDistrict,
  addressToFormData,
  formDataToAddress,
  type NepalAddress,
  updateAddressField,
} from "@/lib/utils/address";

interface AddressSectionProps {
  cart: Cart;
  countries: Country[];
  provinces: NepalProvince[];
  loadingProvinces?: boolean;
  savedAddresses: Address[];
  isAuthenticated: boolean;
  signInUrl: string;
  fetchStates: (countryIso: string) => Promise<State[]>;
  onEmailBlur: (email: string) => Promise<void>;
  onAutoSave: (data: {
    email: string;
    shipping_address?: AddressParams;
    shipping_address_id?: string;
  }) => Promise<void>;
  onUpdateSavedAddress?: (
    id: string,
    data: AddressParams,
  ) => Promise<Address | null>;
  errors?: string[];
  saving?: boolean;
  processing?: boolean;
  user?: User | null;
}

/** Nepal checkout completeness: name + phone + province + district + street + city. */
function isNepalAddressComplete(address: AddressFormData): boolean {
  return (
    address.first_name.trim() !== "" &&
    address.last_name.trim() !== "" &&
    address.phone.trim() !== "" &&
    address.province_id.trim() !== "" &&
    address.district_id.trim() !== "" &&
    address.address1.trim() !== "" &&
    address.city.trim() !== ""
  );
}

export function AddressSection({
  cart,
  countries,
  provinces,
  loadingProvinces,
  savedAddresses: initialSavedAddresses,
  isAuthenticated,
  signInUrl,
  fetchStates,
  onEmailBlur,
  onAutoSave,
  onUpdateSavedAddress,
  errors,
  saving,
  processing,
  user,
}: AddressSectionProps) {
  const t = useTranslations("checkout");
  const tc = useTranslations("common");
  const ta = useTranslations("address");

  // Determine initial saved address: use the first saved address when the
  // cart doesn't have a shipping address yet (authenticated users).
  const initialSavedAddress =
    !cart.shipping_address &&
    isAuthenticated &&
    initialSavedAddresses.length > 0
      ? initialSavedAddresses[0]
      : undefined;

  const [email, setEmail] = useState(cart.email || user?.email || "");
  // Lock the email field only once the account email is actually loaded. The
  // server-derived `isAuthenticated` can be true while the AuthContext `user` is
  // still null — during hydration, or after a transient sync is preserved as
  // `stale` — so keying off `isAuthenticated` alone would leave the field
  // disabled and blank, blocking checkout. Gate on the account email instead.
  const hasAccountEmail = isAuthenticated && !!user?.email;

  const [shipAddress, setShipAddress] = useState<AddressFormData>(() => {
    if (initialSavedAddress) return addressToFormData(initialSavedAddress);
    const formData = addressToFormData(cart.shipping_address);
    // Nepal checkout fixes the country — legacy states leave it blank.
    formData.country_iso = "NP";
    // Pre-fill name from user profile when address has no name yet
    if (!formData.first_name && user?.first_name) {
      formData.first_name = user.first_name;
    }
    if (!formData.last_name && user?.last_name) {
      formData.last_name = user.last_name;
    }
    return formData;
  });
  const [savedAddresses, setSavedAddresses] = useState(initialSavedAddresses);
  const [editingAddress, setEditingAddress] = useState<Address | null>(null);
  const [selectedSavedAddressId, setSelectedSavedAddressId] = useState<
    string | undefined
  >(initialSavedAddress?.id);

  const [shipStates, isPendingShip] = useCountryStates(
    shipAddress.country_iso,
    fetchStates,
  );

  const nepalFormRef = useRef<NepalAddressFormHandle>(null);
  const lastSavedRef = useRef<string>("");
  const mountAutoSaveFiredRef = useRef(false);
  const processingRef = useRef(processing);
  processingRef.current = processing;
  const cartRef = useRef(cart);
  cartRef.current = cart;

  const buildHash = useCallback(
    (emailValue: string, address: AddressFormData, savedAddrId?: string) => {
      if (savedAddrId) {
        return JSON.stringify({
          email: emailValue,
          shipping_address_id: savedAddrId,
        });
      }
      return JSON.stringify({
        email: emailValue,
        shipping_address: formDataToAddress(address),
      });
    },
    [],
  );

  const tryAutoSave = useCallback(
    async (
      currentEmail: string,
      currentAddress: AddressFormData,
      savedAddrId?: string,
    ) => {
      if (!currentEmail.trim()) return;
      if (processingRef.current) return;

      // Saved-address selection: link by id when the district is unchanged,
      // so no duplicate address is created. When the district CHANGES, send
      // the full address data instead — only the data path reverts the cart
      // to the address step and re-estimates delivery rates for the new
      // district (the id path leaves stale rates behind).
      if (savedAddrId) {
        const record = savedAddresses.find((a) => a.id === savedAddrId) as
          | NepalAddress
          | undefined;
        const cartDistrict = (
          cartRef.current?.shipping_address as NepalAddress | null
        )?.district_id;
        const recordNeedsReestimate =
          !record?.district_id || record.district_id !== cartDistrict;

        if (!recordNeedsReestimate) {
          const hash = buildHash(currentEmail, currentAddress, savedAddrId);
          if (hash === lastSavedRef.current) return;
          try {
            await onAutoSave({
              email: currentEmail,
              shipping_address_id: savedAddrId,
            });
            lastSavedRef.current = hash;
          } catch {
            // Allow retry on next blur
          }
          return;
        }

        // District changed (or first address): fall through and save the
        // record's full data so rates re-estimate.
        if (record) {
          const fullData = addressToFormData(record);
          fullData.country_iso = "NP";
          const hash = buildHash(currentEmail, fullData);
          if (hash === lastSavedRef.current) return;
          try {
            await onAutoSave({
              email: currentEmail,
              shipping_address: formDataToAddress(fullData),
            });
            lastSavedRef.current = hash;
          } catch {
            // Allow retry on next blur
          }
          return;
        }
      }

      // Manual form: validate through the Nepal form (inline errors shown)
      // and save only when fully valid.
      const params = await nepalFormRef.current?.getValidParams();
      if (!params) return;

      const hash = buildHash(currentEmail, currentAddress);
      if (hash === lastSavedRef.current) return;
      try {
        await onAutoSave({
          email: currentEmail,
          shipping_address: params,
        });
        lastSavedRef.current = hash;
      } catch {
        // Allow retry on next blur
      }
    },
    [onAutoSave, savedAddresses, buildHash],
  );

  // Auto-save the pre-selected saved address on mount
  useEffect(() => {
    if (mountAutoSaveFiredRef.current) return;
    if (!initialSavedAddress || !email.trim()) return;

    mountAutoSaveFiredRef.current = true;
    tryAutoSave(
      email,
      addressToFormData(initialSavedAddress),
      initialSavedAddress.id,
    );
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [initialSavedAddress, email, tryAutoSave]);

  const updateShipAddress = (field: keyof AddressFormData, value: string) => {
    setShipAddress((prev) => updateAddressField(prev, field, value));
    if (selectedSavedAddressId) {
      setSelectedSavedAddressId(undefined);
    }
  };

  const handleFieldBlur = () => {
    // Skip when a saved address is linked — its data is already on the order
    // (selecting it autosaved immediately).
    if (selectedSavedAddressId) return;
    tryAutoSave(email, shipAddress, selectedSavedAddressId);
  };

  // Only fire auto-save when focus leaves the entire form container,
  // not when moving between internal fields.
  const handleContainerBlur = (e: React.FocusEvent<HTMLDivElement>) => {
    if (e.relatedTarget && e.currentTarget.contains(e.relatedTarget)) return;
    handleFieldBlur();
  };

  const handleEmailBlur = () => {
    // If address is complete, tryAutoSave sends email + address in one call.
    // Only call onEmailBlur (email-only save) when address is incomplete.
    if (isNepalAddressComplete(shipAddress) || selectedSavedAddressId) {
      tryAutoSave(email, shipAddress, selectedSavedAddressId);
    } else {
      onEmailBlur(email);
    }
  };

  const handleSelectSavedAddress = (address: Address) => {
    setShipAddress(addressToFormData(address));
    setSelectedSavedAddressId(address.id);
    // Saved address has all fields filled, trigger auto-save immediately
    tryAutoSave(email, addressToFormData(address), address.id);
  };

  const handleSaveEditedAddress = async (data: AddressParams, id?: string) => {
    if (!id || !onUpdateSavedAddress) {
      throw new Error("Cannot update address");
    }

    const updatedAddress = await onUpdateSavedAddress(id, data);
    if (!updatedAddress) {
      throw new Error("Failed to update address");
    }

    setSavedAddresses((prev) =>
      prev.map((addr) => (addr.id === id ? updatedAddress : addr)),
    );
    handleSelectSavedAddress(updatedAddress);
  };

  // Warn when the linked address still needs a district (legacy addresses).
  const linkedNeedsDistrict =
    !!selectedSavedAddressId &&
    addressNeedsDistrict(
      savedAddresses.find((a) => a.id === selectedSavedAddressId),
    );

  return (
    <>
      {/* Errors */}
      {errors && errors.length > 0 && (
        <div className="rounded-sm border border-red-300 bg-red-50 px-4 py-3 mb-4">
          {errors.map((err, i) => (
            <p key={i} className="text-sm text-red-700">
              {err}
            </p>
          ))}
        </div>
      )}

      {/* Contact section */}
      <div className="mb-6">
        <div className="flex items-baseline justify-between mb-3">
          <h2 className="text-lg font-bold text-gray-900">
            {t("contactInformation")}
          </h2>
          {!isAuthenticated && (
            <Link
              href={signInUrl}
              className="text-[13px] text-gray-700 underline underline-offset-2 hover:text-black"
            >
              {t("signIn")}
            </Link>
          )}
        </div>
        <Input
          type="email"
          id="email"
          required
          value={email}
          onChange={(e) => setEmail(e.target.value)}
          onBlur={handleEmailBlur}
          disabled={hasAccountEmail}
          placeholder={t("emailAddress")}
        />
        {hasAccountEmail && (
          <p className="text-xs text-gray-500 mt-1.5">
            {t("usingAccountEmail")}
          </p>
        )}
      </div>

      {/* Delivery section */}
      <div>
        <div className="flex items-center justify-between mb-3">
          <h2 className="text-lg font-bold text-gray-900">
            {t("shippingAddress")}
          </h2>
          {saving && (
            <span className="flex items-center gap-1.5 text-xs text-gray-400">
              <Loader2 className="h-3 w-3 animate-spin" />
              {tc("saving")}
            </span>
          )}
        </div>
        {linkedNeedsDistrict && (
          <p className="rounded-sm border border-amber-300 bg-amber-50 px-4 py-2.5 mb-3 text-sm text-amber-800">
            {t("selectDistrictPrompt")}
          </p>
        )}
        {isAuthenticated && savedAddresses.length > 0 ? (
          <AddressSelector
            savedAddresses={savedAddresses}
            currentAddress={shipAddress}
            countries={countries}
            states={shipStates}
            loadingStates={isPendingShip}
            provinces={provinces}
            loadingProvinces={loadingProvinces}
            nepalFormRef={nepalFormRef}
            onChange={updateShipAddress}
            onSelectSavedAddress={handleSelectSavedAddress}
            onEditAddress={
              onUpdateSavedAddress
                ? (address) => setEditingAddress(address)
                : undefined
            }
            onFieldBlur={handleFieldBlur}
            idPrefix="ship"
            user={user}
          />
        ) : (
          <div onBlur={handleContainerBlur}>
            <AddressFormFields
              address={shipAddress}
              countries={countries}
              states={shipStates}
              loadingStates={isPendingShip}
              onChange={updateShipAddress}
              idPrefix="ship"
              nepalProvinces={provinces}
              loadingNepalProvinces={loadingProvinces}
              nepalFormRef={nepalFormRef}
              onNepalBlur={handleFieldBlur}
            />
          </div>
        )}
      </div>

      {/* Edit Address Modal */}
      {editingAddress && (
        <AddressEditModal
          address={editingAddress}
          countries={countries}
          provinces={provinces}
          fetchStates={fetchStates}
          onSave={handleSaveEditedAddress}
          onClose={() => setEditingAddress(null)}
          title={ta("editAddress")}
        />
      )}
    </>
  );
}
