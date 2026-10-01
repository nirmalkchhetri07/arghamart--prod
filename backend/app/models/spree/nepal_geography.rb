# frozen_string_literal: true

# Canonical Nepal geography: 7 provinces + 77 districts.
#
# Single source of truth for seeds, data migrations, and specs.
# Shipping fees start at 0 ("no fee set yet") — Part 4 (admin manage-fee)
# is where merchants configure real NPR fees. District names use the
# official English spellings; Nawalparasi is split into Nawalpur (East,
# Gandaki) and Parasi (West, Lumbini), and Rukum into East (Lumbini) /
# West (Karnali).
module Spree
  module NepalGeography
    PROVINCES = [
      { code: 'KOSHI', name: 'Koshi', position: 1,
        districts: %w[Bhojpur Dhankuta Ilam Jhapa Khotang Morang Okhaldhunga Panchthar Sankhuwasabha Solukhumbu Sunsari Taplejung Terhathum Udayapur] },
      { code: 'MADHESH', name: 'Madhesh', position: 2,
        districts: %w[Bara Dhanusha Mahottari Parsa Rautahat Saptari Sarlahi Siraha] },
      { code: 'BAGMATI', name: 'Bagmati', position: 3,
        districts: ['Bhaktapur', 'Chitwan', 'Dhading', 'Dolakha', 'Kathmandu', 'Kavrepalanchok', 'Lalitpur', 'Makwanpur', 'Nuwakot', 'Ramechhap', 'Rasuwa', 'Sindhuli', 'Sindhupalchok'] },
      { code: 'GANDAKI', name: 'Gandaki', position: 4,
        districts: %w[Baglung Gorkha Kaski Lamjung Manang Mustang Myagdi Nawalpur Parbat Syangja Tanahun] },
      { code: 'LUMBINI', name: 'Lumbini', position: 5,
        districts: ['Arghakhanchi', 'Banke', 'Bardiya', 'Dang', 'Gulmi', 'Kapilvastu', 'Parasi', 'Palpa', 'Pyuthan', 'Rolpa', 'Rukum East', 'Rupandehi'] },
      { code: 'KARNALI', name: 'Karnali', position: 6,
        districts: %w[Dailekh Dolpa Humla Jajarkot Jumla Kalikot Mugu Salyan Surkhet] + ['Rukum West'] },
      { code: 'SUDURPASHCHIM', name: 'Sudurpashchim', position: 7,
        districts: %w[Achham Baitadi Bajhang Bajura Dadeldhura Darchula Doti Kailali Kanchanpur] }
    ].freeze

    def self.seed!
      PROVINCES.each do |attrs|
        province = Spree::Province.find_or_create_by!(code: attrs[:code]) do |p|
          p.name = attrs[:name]
          p.position = attrs[:position]
        end
        province.update!(name: attrs[:name], position: attrs[:position])

        attrs[:districts].each do |district_name|
          Spree::District.find_or_create_by!(province: province, name: district_name) do |d|
            d.shipping_fee = 0
            d.active = true
          end
        end
      end
    end
  end
end
