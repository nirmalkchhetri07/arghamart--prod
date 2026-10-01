# frozen_string_literal: true

# Nepal checkout addresses (Parts 1-2).
#
# Columns (see AddProvinceAndDistrictToSpreeAddresses):
#   province_id / district_id — nullable FKs so existing orders and saved
#   addresses keep validating without a backfill.
#
# Rules:
# - firstname/lastname + phone always required (zip is optional — overrides
#   Spree's per-country zipcode requirement for the Nepal-only market).
# - phone must look like a Nepali number: mobile 97/98 + 8 digits with
#   optional +977 prefix, or common landline formats (01-XXXXXXX, etc.).
# - when both province + district are present, the district must belong to
#   the province.
module Spree
  module AddressDecorator
    NEPALI_MOBILE_RE = /\A(\+977)?(97|98)\d{8}\z/ unless const_defined?(:NEPALI_MOBILE_RE)
    # Landlines: 01-XXXXXXX (Kathmandu), 0XX-XXXXXX elsewhere, with optional
    # +977 prefix (where the trunk 0 is dropped: +977-1-XXXXXXX).
    NEPALI_LANDLINE_RE = /\A(\+977)?0?\d{8,9}\z/ unless const_defined?(:NEPALI_LANDLINE_RE)

    def self.prepended(base)
      base.belongs_to :province,
                      class_name: 'Spree::Province',
                      foreign_key: :province_id,
                      inverse_of: :addresses,
                      optional: true
      base.belongs_to :district,
                      class_name: 'Spree::District',
                      foreign_key: :district_id,
                      inverse_of: :addresses,
                      optional: true

      base.validate :district_belongs_to_province
      base.validate :nepali_phone_format

      base.whitelisted_ransackable_attributes =
        (base.whitelisted_ransackable_attributes || []) | %w[province_id district_id]
    end

    # API sends prefixed IDs (prov_xxx / dist_xxx) for province/district —
    # resolve them to integer FKs before assignment. Raw integer IDs pass
    # through untouched so seeds/admin forms keep working.
    def province_id=(value)
      super(resolve_province_id(value))
    end

    def district_id=(value)
      super(resolve_district_id(value))
    end

    # Checkout sends province/district by name as a fallback (guest flows).
    # Resolve to FKs; unknown names leave the FK untouched so the presence
    # validation below can report the problem.
    def province_name=(value)
      return if value.blank?

      self.province = Spree::Province.where('LOWER(name) = ?', value.to_s.strip.downcase).take || province
    end

    def district_name=(value)
      return if value.blank?

      scope = Spree::District.where('LOWER(name) = ?', value.to_s.strip.downcase)
      scope = scope.where(province_id: province_id) if province_id.present?
      self.district = scope.take || district
    end

    def province_name
      province&.name
    end

    def district_name
      district&.name
    end

    # Part 1 requires phone on every Nepal checkout address. Spree's default
    # is opt-in via Spree::Config[:address_requires_phone] (false) — force it
    # on for Nepal addresses only so US factory addresses and non-NP
    # checkouts keep Spree's default behavior. The explicit check in
    # CheckoutPageContent (phoneRequired) stays as the user-facing guard.
    def require_phone?
      return true if nepali_address?

      super
    end

    # Part 1 makes zip/postal code optional. Spree requires it per-country
    # (country.zipcode_required?) — relax it globally; Nepal addresses
    # rarely use postal codes and the storefront sends it as optional.
    def require_zipcode?
      false
    end

    private

    def district_belongs_to_province
      return if province_id.blank? || district_id.blank?
      return if district&.province_id == province_id

      errors.add(:district, :invalid)
    end

    def nepali_phone_format
      return if phone.blank? # presence is handled by require_phone?
      return unless nepali_address?

      normalized = phone.to_s.gsub(/[ \-\u2013\u2014]/, '')
      return if normalized.match?(NEPALI_MOBILE_RE) || normalized.match?(NEPALI_LANDLINE_RE)

      errors.add(:phone, :invalid)
    end

    # Only Nepal addresses get the strict Nepali format check — other
    # countries keep Spree's Phonelib validation so guest checkouts and
    # Spree factories with US addresses keep working.
    def nepali_address?
      country_iso == 'NP' || province_id.present? || district_id.present?
    end

    def resolve_province_id(value)
      return value if value.blank? || value.is_a?(Integer)

      str = value.to_s
      return str unless str.start_with?('prov_')

      Spree::Province.find_by_prefix_id(str)&.id || value
    end

    def resolve_district_id(value)
      return value if value.blank? || value.is_a?(Integer)

      str = value.to_s
      return str unless str.start_with?('dist_')

      Spree::District.find_by_prefix_id(str)&.id || value
    end
  end

  Address.prepend AddressDecorator
end
