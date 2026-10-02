# frozen_string_literal: true

# Node equivalent: a pure service module that builds the NCM create-order request body.
module Ncm
  class PayloadBuilder
    DELIVERY_TYPES = Spree::NcmDeliveryRate::DELIVERY_TYPES
    class ValidationError < StandardError; end

    def initialize(shipment:, partner:)
      @shipment = shipment
      @order = shipment.order
      @partner = partner
      @address = @order.shipping_address
    end

    def call
      BranchCatalog.ensure!
      validate!
      items = package_items
      weight = total_weight
      cod = CodCalculator.new(
        order: @order,
        include_delivery_charge: @partner.include_delivery_charge_in_cod?
      ).remaining

      {
        name: receiver_name,
        phone: normalized_phone(@address.phone),
        phone2: normalized_phone(@address.phone2),
        address: full_address,
        fbranch: origin.name,
        branch: destination.name,
        cod_charge: money(cod),
        shipping_charge: money(delivery_charge),
        package: render_template(@shipment.ncm_package_override.presence || @partner.package_template, items:),
        package_type: @shipment.ncm_package_type.presence || @partner.default_package_type,
        vref_id: @order.id.to_s,
        delivery_type: delivery_type,
        weight: weight.to_s('F'),
        handling: fragile? ? 'Fragile' : 'Non-Fragile',
        instruction: render_template(
          @shipment.ncm_instruction_override.presence || @partner.instruction_template,
          order_number: @order.number,
          customer_note: @order.customer_note.to_s
        )
      }.compact
    end

    def total_weight
      fallback = @partner.fallback_weight_kg.to_d
      quantity_weight = @shipment.inventory_units.includes(variant: :product).sum do |unit|
        variant_weight = unit.variant.weight.to_d
        (variant_weight.positive? ? variant_weight : fallback) * unit.quantity.to_i
      end
      quantity_weight.round(3)
    end

    def delivery_charge
      charge = @shipment.ncm_delivery_charge || DeliveryChargeCalculator.call(
        origin: origin,
        destination: destination,
        delivery_type: delivery_type,
        weight_kg: total_weight
      )
      @shipment.update_column(:ncm_delivery_charge, charge) if @shipment.persisted? && @shipment.ncm_delivery_charge != charge
      charge
    end

    private

    def validate!
      raise ValidationError, 'A shipping address is required' unless @address
      raise ValidationError, 'Receiver first and last name are required' if receiver_name.blank?
      raise ValidationError, 'A valid 10-digit Nepali mobile number is required' unless normalized_phone(@address.phone)&.match?(/\A9[78]\d{8}\z/)
      raise ValidationError, 'Province/state is required' if @address.province.blank? && @address.state_name.blank?
      raise ValidationError, 'District is required' unless @address.district
      raise ValidationError, 'Municipality/locality is required' if @address.city.blank?
      raise ValidationError, 'Delivery type is required' unless DELIVERY_TYPES.include?(delivery_type)
      raise ValidationError, 'Origin NCM branch is required' unless origin
      raise ValidationError, 'Destination NCM branch is required' unless destination
      raise ValidationError, 'Package description is required' if package_items.blank?
      raise ValidationError, 'COD amount is required' if CodCalculator.new(order: @order).remaining.nil?
      raise ValidationError, 'Delivery charge is not configured for this route' if delivery_charge.nil?
    rescue CodCalculator::OverpaymentError, DeliveryChargeCalculator::UnavailableError => e
      raise ValidationError, e.message
    end

    def receiver_name
      [@address&.firstname, @address&.lastname].compact_blank.join(' ')
    end

    def origin
      branch_code = @shipment.ncm_origin_branch.presence || @partner.default_origin_branch
      Spree::NcmBranch.active.find_by(code: branch_code) ||
        Spree::NcmBranch.active.find_by('LOWER(name) = ?', branch_code.to_s.downcase)
    end

    def destination
      branch_code = @shipment.ncm_destination_branch
      return Spree::NcmBranch.active.find_by(code: branch_code) if branch_code.present?

      resolution = DestinationResolver.call(address: @address)
      @shipment.update_columns(ncm_branch_resolution: resolution.source, ncm_review_reason: resolution.reason) if @shipment.persisted?
      resolution.branch
    end

    def delivery_type
      @shipment.ncm_delivery_type.presence || @partner.default_delivery_type
    end

    def package_items
      @shipment.inventory_units.includes(variant: :product).map do |unit|
        "#{unit.variant.product.name} x#{unit.quantity}"
      end.join(', ')
    end

    def fragile?
      @shipment.inventory_units.includes(variant: { product: :taxons }).any? do |unit|
        product = unit.variant.product
        product.ncm_handling.to_s.casecmp('fragile').zero? ||
          product.taxons.any? { |taxon| taxon.ncm_handling.to_s.casecmp('fragile').zero? }
      end
    end

    def full_address
      [@address.address1, @address.address2, @address.city, @address.district&.name,
       @address.province&.name || @address.state_name].compact_blank.join(', ')
    end

    def normalized_phone(phone)
      digits = phone.to_s.gsub(/\D/, '')
      digits = digits.delete_prefix('977')
      digits.presence
    end

    def money(value)
      BigDecimal(value.to_s).round(2).to_s('F')
    end

    def render_template(template, values)
      template.to_s.gsub(/\{([a-z_]+)\}/) { values.fetch(Regexp.last_match(1).to_sym, '') }.squish
    end
  end
end