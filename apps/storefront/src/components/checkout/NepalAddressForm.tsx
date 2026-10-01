"use client";

import { zodResolver } from "@hookform/resolvers/zod";
import { Check, ChevronsUpDown } from "lucide-react";
import { useLocale, useTranslations } from "next-intl";
import {
  forwardRef,
  useEffect,
  useImperativeHandle,
  useMemo,
  useState,
} from "react";
import { useForm, useWatch } from "react-hook-form";
import { Button } from "@/components/ui/button";
import {
  Command,
  CommandEmpty,
  CommandGroup,
  CommandInput,
  CommandItem,
  CommandList,
} from "@/components/ui/command";
import {
  Form,
  FormControl,
  FormField,
  FormItem,
  FormLabel,
  useFormField,
} from "@/components/ui/form";
import { Input } from "@/components/ui/input";
import {
  Popover,
  PopoverContent,
  PopoverTrigger,
} from "@/components/ui/popover";
import type { NepalProvince } from "@/lib/data/nepal";
import {
  formatMunicipalityOption,
  getMunicipalitiesForDistrict,
} from "@/lib/data/nepal-municipalities";
import { cn } from "@/lib/utils";
import {
  type NepalAddressData,
  type NepalAddressFormValues,
  nepalAddressSchema,
  splitFullName,
} from "@/lib/validation/nepal-address";

export interface NepalAddressParams {
  first_name: string;
  last_name: string;
  address1: string;
  city: string;
  postal_code: string;
  phone: string;
  country_iso: "NP";
  province_id: string;
  district_id: string;
}

export interface NepalAddressFormHandle {
  /**
   * Validate and return the backend-ready address params (country fixed to
   * NP, full name split, phone canonicalized), or null when invalid. Marks
   * fields as touched so inline errors appear.
   */
  getValidParams: () => Promise<NepalAddressParams | null>;
  /** Replace all field values (e.g. when a saved address is selected). */
  resetValues: (values: Partial<NepalAddressFormValues>) => void;
}

interface NepalAddressFormProps {
  provinces: NepalProvince[];
  loadingProvinces?: boolean;
  defaultValues?: Partial<NepalAddressFormValues>;
  /** Live values for parent autosave flows. */
  onChange?: (values: NepalAddressFormValues, valid: boolean) => void;
  /** Fired when focus leaves any field (parent triggers autosave). */
  onFieldBlur?: () => void;
  /** Optional outer form id — a parent submit button can target it. */
  formId?: string;
  onValidSubmit?: (params: NepalAddressParams) => Promise<void> | void;
  idPrefix: string;
  disabled?: boolean;
}

export function toNepalParams(data: NepalAddressData): NepalAddressParams {
  const { first_name, last_name } = splitFullName(data.fullName);
  return {
    first_name,
    last_name,
    address1: data.address1,
    city: data.city,
    postal_code: data.postalCode ?? "",
    phone: data.phone,
    country_iso: "NP",
    province_id: data.provinceId,
    district_id: data.districtId,
  };
}

interface ComboboxProps {
  label: string;
  placeholder: string;
  searchPlaceholder: string;
  emptyText: string;
  options: { id: string; name: string }[];
  value: string;
  onSelect: (id: string) => void;
  disabled?: boolean;
  idPrefix: string;
  field: string;
}

function Combobox({
  label,
  placeholder,
  searchPlaceholder,
  emptyText,
  options,
  value,
  onSelect,
  disabled,
  idPrefix,
  field,
}: ComboboxProps) {
  const [open, setOpen] = useState(false);
  const selected = options.find((o) => o.id === value);

  return (
    <Popover open={open} onOpenChange={setOpen}>
      <PopoverTrigger asChild>
        <Button
          id={`${idPrefix}-${field}`}
          variant="outline"
          role="combobox"
          aria-expanded={open}
          aria-label={label}
          disabled={disabled}
          className="w-full justify-between font-normal"
        >
          <span className="truncate">
            {selected ? selected.name : placeholder}
          </span>
          <ChevronsUpDown className="ml-2 h-4 w-4 shrink-0 opacity-50" />
        </Button>
      </PopoverTrigger>
      <PopoverContent
        className="w-(--radix-popover-trigger-width) p-0"
        align="start"
      >
        <Command>
          <CommandInput placeholder={searchPlaceholder} />
          <CommandList>
            <CommandEmpty>{emptyText}</CommandEmpty>
            <CommandGroup>
              {options.map((option) => (
                <CommandItem
                  key={option.id}
                  value={option.name}
                  onSelect={() => {
                    onSelect(option.id);
                    setOpen(false);
                  }}
                >
                  <Check
                    className={cn(
                      "mr-2 h-4 w-4",
                      value === option.id ? "opacity-100" : "opacity-0",
                    )}
                  />
                  {option.name}
                </CommandItem>
              ))}
            </CommandGroup>
          </CommandList>
        </Command>
      </PopoverContent>
    </Popover>
  );
}

function FormMessage() {
  const t = useTranslations("address");
  const { error, formMessageId } = useFormField();
  if (!error?.message) return null;
  // Schema errors are message keys — resolve them per locale.
  return (
    <p
      data-slot="form-message"
      id={formMessageId}
      className="text-destructive text-sm"
    >
      {t(error.message)}
    </p>
  );
}

export const NepalAddressForm = forwardRef<
  NepalAddressFormHandle,
  NepalAddressFormProps
>(function NepalAddressForm(
  {
    provinces,
    loadingProvinces,
    defaultValues,
    onChange,
    onFieldBlur,
    formId,
    onValidSubmit,
    idPrefix,
    disabled,
  },
  ref,
) {
  const t = useTranslations("address");
  const tc = useTranslations("common");
  const locale = useLocale();

  const form = useForm<NepalAddressFormValues>({
    resolver: zodResolver(nepalAddressSchema),
    defaultValues: {
      fullName: "",
      phone: "",
      provinceId: "",
      districtId: "",
      address1: "",
      city: "",
      postalCode: "",
      ...defaultValues,
    },
    mode: "onTouched",
  });

  const provinceId = useWatch({ control: form.control, name: "provinceId" });
  const districtId = useWatch({ control: form.control, name: "districtId" });
  const cityValue = useWatch({ control: form.control, name: "city" });
  const allValues = useWatch({ control: form.control });

  const districts = useMemo(
    () => provinces.find((p) => p.id === provinceId)?.districts ?? [],
    [provinces, provinceId],
  );

  const districtName = useMemo(() => {
    for (const province of provinces) {
      const district = province.districts.find((d) => d.id === districtId);
      if (district) return district.name;
    }
    return "";
  }, [provinces, districtId]);

  // Municipalities unlock once a district is selected. Matched by district
  // name against the static local-level dataset (aliases cover the few
  // backend-vs-source spelling differences).
  const municipalities = useMemo(
    () => getMunicipalitiesForDistrict(districtName),
    [districtName],
  );

  const municipalityOptions = useMemo(() => {
    const options = municipalities.map((level) => ({
      id: level.name_en,
      name: formatMunicipalityOption(level, locale),
    }));
    // Keep previously saved custom cities visible instead of dropping them
    // when they aren't in the dataset (legacy free-text addresses).
    if (cityValue && !options.some((o) => o.id === cityValue)) {
      options.push({ id: cityValue, name: cityValue });
    }
    return options;
  }, [municipalities, cityValue, locale]);

  // Changing the province clears the district (it belongs to the old one),
  // and the municipality along with it.
  const handleProvinceSelect = (id: string) => {
    form.setValue("provinceId", id, {
      shouldValidate: true,
      shouldTouch: true,
    });
    form.setValue("districtId", "", { shouldValidate: true });
    form.setValue("city", "", { shouldValidate: true });
  };

  // Changing the district clears the municipality (it belongs to the old one).
  const handleDistrictSelect = (id: string) => {
    form.setValue("districtId", id, {
      shouldValidate: true,
      shouldTouch: true,
    });
    form.setValue("city", "", { shouldValidate: true });
  };

  // Live values for parent autosave flows (guarded against unchanged
  // values so parents can safely mirror into state).
  const lastSentRef = useState(() => ({ hash: "" }))[0];
  useEffect(() => {
    const hash = JSON.stringify(allValues);
    if (hash === lastSentRef.hash) return;
    lastSentRef.hash = hash;
    onChange?.(allValues as NepalAddressFormValues, form.formState.isValid);
  }, [allValues, form.formState.isValid, onChange, lastSentRef]);

  useImperativeHandle(ref, () => ({
    getValidParams: async () => {
      const valid = await form.trigger();
      if (!valid) return null;
      return toNepalParams(form.getValues() as NepalAddressData);
    },
    resetValues: (values) => {
      form.reset({ ...form.getValues(), ...values });
    },
  }));

  const handleSubmit = form.handleSubmit(async (data) => {
    await onValidSubmit?.(toNepalParams(data as NepalAddressData));
  });

  return (
    <Form {...form}>
      <form
        id={formId}
        onSubmit={onValidSubmit ? handleSubmit : (e) => e.preventDefault()}
        onBlur={onFieldBlur}
        className="flex flex-col gap-3"
      >
        <FormField
          control={form.control}
          name="fullName"
          render={({ field }) => (
            <FormItem>
              <FormLabel htmlFor={`${idPrefix}-fullName`}>
                {t("fullName")}
              </FormLabel>
              <FormControl>
                <Input
                  id={`${idPrefix}-fullName`}
                  autoComplete="name"
                  placeholder={t("fullName")}
                  disabled={disabled}
                  {...field}
                />
              </FormControl>
              <FormMessage />
            </FormItem>
          )}
        />

        <FormField
          control={form.control}
          name="phone"
          render={({ field }) => (
            <FormItem>
              <FormLabel htmlFor={`${idPrefix}-phone`}>{t("phone")}</FormLabel>
              <FormControl>
                <Input
                  id={`${idPrefix}-phone`}
                  type="tel"
                  autoComplete="tel"
                  inputMode="tel"
                  placeholder="98XXXXXXXX"
                  disabled={disabled}
                  {...field}
                />
              </FormControl>
              <FormMessage />
            </FormItem>
          )}
        />

        <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
          <FormField
            control={form.control}
            name="provinceId"
            render={({ field }) => (
              <FormItem>
                <FormLabel>{t("province")}</FormLabel>
                <FormControl>
                  <Combobox
                    label={t("province")}
                    placeholder={
                      loadingProvinces ? tc("loading") : t("selectProvince")
                    }
                    searchPlaceholder={t("searchProvince")}
                    emptyText={t("noProvinceFound")}
                    options={provinces.map((p) => ({ id: p.id, name: p.name }))}
                    value={field.value}
                    onSelect={handleProvinceSelect}
                    disabled={disabled || loadingProvinces}
                    idPrefix={idPrefix}
                    field="province"
                  />
                </FormControl>
                <FormMessage />
              </FormItem>
            )}
          />

          <FormField
            control={form.control}
            name="districtId"
            render={({ field }) => (
              <FormItem>
                <FormLabel>{t("district")}</FormLabel>
                <FormControl>
                  <Combobox
                    label={t("district")}
                    placeholder={
                      !provinceId
                        ? t("selectProvinceFirst")
                        : t("selectDistrict")
                    }
                    searchPlaceholder={t("searchDistrict")}
                    emptyText={t("noDistrictFound")}
                    options={districts.map((d) => ({ id: d.id, name: d.name }))}
                    value={field.value}
                    onSelect={handleDistrictSelect}
                    disabled={disabled || !provinceId}
                    idPrefix={idPrefix}
                    field="district"
                  />
                </FormControl>
                <FormMessage />
              </FormItem>
            )}
          />
        </div>

        <FormField
          control={form.control}
          name="address1"
          render={({ field }) => (
            <FormItem>
              <FormLabel htmlFor={`${idPrefix}-address1`}>
                {t("streetAddress")}
              </FormLabel>
              <FormControl>
                <Input
                  id={`${idPrefix}-address1`}
                  autoComplete="street-address"
                  placeholder={t("streetAddress")}
                  disabled={disabled}
                  {...field}
                />
              </FormControl>
              <FormMessage />
            </FormItem>
          )}
        />

        <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
          <FormField
            control={form.control}
            name="city"
            render={({ field }) => (
              <FormItem>
                <FormLabel htmlFor={`${idPrefix}-city`}>
                  {t("cityMunicipality")}
                </FormLabel>
                <FormControl>
                  {municipalities.length > 0 ? (
                    <Combobox
                      label={t("cityMunicipality")}
                      placeholder={
                        !districtId
                          ? t("selectDistrictFirst")
                          : t("selectMunicipality")
                      }
                      searchPlaceholder={t("searchMunicipality")}
                      emptyText={t("noMunicipalityFound")}
                      options={municipalityOptions}
                      value={field.value}
                      onSelect={(id) =>
                        form.setValue("city", id, {
                          shouldValidate: true,
                          shouldTouch: true,
                        })
                      }
                      disabled={disabled || !districtId}
                      idPrefix={idPrefix}
                      field="city"
                    />
                  ) : (
                    <Input
                      id={`${idPrefix}-city`}
                      autoComplete="address-level2"
                      placeholder={t("cityMunicipality")}
                      disabled={disabled || !districtId}
                      {...field}
                    />
                  )}
                </FormControl>
                <FormMessage />
              </FormItem>
            )}
          />

          <FormField
            control={form.control}
            name="postalCode"
            render={({ field }) => (
              <FormItem>
                <FormLabel htmlFor={`${idPrefix}-postalCode`}>
                  {t("zipCodeOptional")}
                </FormLabel>
                <FormControl>
                  <Input
                    id={`${idPrefix}-postalCode`}
                    autoComplete="postal-code"
                    inputMode="numeric"
                    placeholder={t("zipCodeOptional")}
                    disabled={disabled}
                    {...field}
                  />
                </FormControl>
                <FormMessage />
              </FormItem>
            )}
          />
        </div>
      </form>
    </Form>
  );
});
