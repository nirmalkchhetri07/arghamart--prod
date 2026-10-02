# frozen_string_literal: true

class SeedNcmBranches < ActiveRecord::Migration[8.1]
  BRANCHES = {
    'TINK1' => 'TINKUNE',
    'POKH1' => 'POKHARA',
    'BUTW1' => 'BUTWAL',
    'DAMA1' => 'DAMAK',
    'JANA1' => 'JANAKPUR',
    'SANK1' => 'SANKHU'
  }.freeze

  def up
    now = Time.current
    BRANCHES.each do |code, name|
      execute <<~SQL.squish
        INSERT INTO spree_ncm_branches (name, code, active, created_at, updated_at)
        VALUES (#{connection.quote(name)}, #{connection.quote(code)}, TRUE, #{connection.quote(now)}, #{connection.quote(now)})
        ON CONFLICT (code) DO UPDATE SET name = EXCLUDED.name, active = TRUE, updated_at = EXCLUDED.updated_at
      SQL
    end

    mapped_districts = {
      'BUTW1' => 'Rupandehi',
      'POKH1' => 'Kaski',
      'DAMA1' => 'Jhapa',
      'JANA1' => 'Dhanusha'
    }
    mapped_districts.each { |code, district_name| map_branch(code, district_name, 'district') }
    map_branch('TINK1', 'Kathmandu', 'municipality', 'Tinkune')
    map_branch('SANK1', 'Kathmandu', 'municipality', 'Sankhu')
    map_branch('BUTW1', 'Arghakhanchi', 'nearest')

    execute <<~SQL.squish
      UPDATE spree_districts SET name_aliases = '["Arghakhachi"]'::jsonb
      WHERE LOWER(name) = 'arghakhanchi' AND name_aliases = '[]'::jsonb
    SQL
  end

  def down
    execute "DELETE FROM spree_ncm_branch_mappings WHERE source IN ('district', 'nearest')"
    execute "DELETE FROM spree_ncm_branches WHERE code IN (#{BRANCHES.keys.map { |code| connection.quote(code) }.join(', ')})"
  end

  private

  def map_branch(code, district_name, source, municipality = nil)
    execute <<~SQL.squish
      INSERT INTO spree_ncm_branch_mappings (branch_id, district_id, municipality, source, active, created_at, updated_at)
      SELECT b.id, d.id, #{connection.quote(municipality)}, #{connection.quote(source)}, TRUE, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
      FROM spree_ncm_branches b
      JOIN spree_districts d ON LOWER(d.name) = LOWER(#{connection.quote(district_name)})
      WHERE b.code = #{connection.quote(code)}
      ON CONFLICT DO NOTHING
    SQL
  end
end

# Node equivalent: a data migration that seeds known NCM branches and explicit Nepal destination mappings.