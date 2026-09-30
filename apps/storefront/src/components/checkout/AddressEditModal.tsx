"use client";

import type { AddressParams, Country, State } from "@spree/sdk";
import { CircleAlert } from "lucide-react";
import { useTranslations } from "next-intl";
import { useState } from "react";
import { AddressFormFields } from "@/components/checkout/AddressFormFields";
import {
  NepalAddressForm,
  type NepalAddressParams,
} from "@/components/checkout/NepalAddressForm";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogTitle } from "@/components/ui/dialog";
import type { User } from "@/contexts/AuthContext";
import { useCountryStates } from "@/hooks/useCountryStates";
import type { NepalProvince } from "@/lib/data/nepal";
import {
  type AddressFormData,
  addressFullName,
  addressToFormData,
  emptyAddress,
  formDataToAddress,
  type NepalAddress,
  updateAddressField,
} from "@/lib/utils/address";

interface AddressEditModalProps {
  address:
    | ({
        id?: string;
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
      } & Partial<NepalAddress>)
    | null;
  countries: Country[];
  /** When provided, the modal uses the Nepal form (fixed NP country). */
  provinces?: NepalProvince[];
  fetchStates: (countryIso: string) => Promise<State[]>;
  onSave: (data: AddressParams, id?: string) => Promise<void>;
  onClose: () => void;
  title?: string;
  user?: User | null;
}

export function AddressEditModal({
  address,
  countries,
  provinces,
  fetchStates,
  onSave,
  onClose,
  title,
  user,
}: AddressEditModalProps) {
  const t = useTranslations("address");
  const tc = useTranslations("common");

  // Generic mode state (unchanged legacy behavior for non-Nepal flows).
  const [formData, setFormData] = useState<AddressFormData>(() => {
    if (address) return addressToFormData(address);
    return {
      ...emptyAddress,
      first_name: user?.first_name || "",
      last_name: user?.last_name || "",
    };
  });
  const [states, loadingStates] = useCountryStates(
    formData.country_iso,
    fetchStates,
    !provinces,
  );
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const nepalFormId = `nepal-address-${address?.id ?? "new"}`;

  const handleChange = (field: keyof AddressFormData, value: string) => {
    setFormData((prev) => updateAddressField(prev, field, value));
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError(null);
    setSaving(true);

    try {
      await onSave(formDataToAddress(formData), address?.id);
      onClose();
    } catch (err) {
      setError(err instanceof Error ? err.message : t("failedToSave"));
    } finally {
      setSaving(false);
    }
  };

  const handleNepalValidSubmit = async (params: NepalAddressParams) => {
    setError(null);
    setSaving(true);
    try {
      await onSave(params, address?.id);
      onClose();
    } catch (err) {
      setError(err instanceof Error ? err.message : t("failedToSave"));
    } finally {
      setSaving(false);
    }
  };

  const modalTitle =
    title ?? (address?.id ? t("editAddress") : t("addNewAddress"));

  // Prefill the Nepal form from the saved (possibly legacy) address.
  const nepalDefaults = {
    fullName:
      addressFullName(address) ||
      [user?.first_name, user?.last_name].filter(Boolean).join(" "),
    phone: address?.phone || "",
    provinceId: (address as NepalAddress)?.province_id || "",
    districtId: (address as NepalAddress)?.district_id || "",
    address1: address?.address1 || "",
    city: address?.city || "",
    postalCode: address?.postal_code || "",
  };

  return (
    <Dialog
      open={true}
      onOpenChange={(open) => {
        if (!open) onClose();
      }}
    >
      <DialogContent className="sm:max-w-lg p-0 gap-0" showCloseButton={false}>
        <div className="px-4 pt-5 pb-4 sm:p-6">
          <DialogTitle className="text-lg font-medium text-gray-900 mb-4">
            {modalTitle}
          </DialogTitle>

          {error && (
            <Alert variant="destructive">
              <CircleAlert />
              <AlertDescription>{error}</AlertDescription>
            </Alert>
          )}

          {provinces ? (
            <NepalAddressForm
              provinces={provinces}
              defaultValues={nepalDefaults}
              formId={nepalFormId}
              onValidSubmit={handleNepalValidSubmit}
              idPrefix="modal"
            />
          ) : (
            <form onSubmit={handleSubmit}>
              <AddressFormFields
                address={formData}
                countries={countries}
                states={states}
                loadingStates={loadingStates}
                onChange={handleChange}
                idPrefix="modal"
              />
              <div className="border-t border-gray-200 px-4 py-3 sm:px-6 sm:flex sm:flex-row-reverse gap-3">
                <Button type="submit" disabled={saving}>
                  {saving ? tc("saving") : t("saveAddress")}
                </Button>
                <Button type="button" variant="outline" onClick={onClose}>
                  {tc("cancel")}
                </Button>
              </div>
            </form>
          )}
        </div>

        {provinces && (
          <div className="border-t border-gray-200 px-4 py-3 sm:px-6 sm:flex sm:flex-row-reverse gap-3">
            <Button type="submit" form={nepalFormId} disabled={saving}>
              {saving ? tc("saving") : t("saveAddress")}
            </Button>
            <Button type="button" variant="outline" onClick={onClose}>
              {tc("cancel")}
            </Button>
          </div>
        )}
      </DialogContent>
    </Dialog>
  );
}
