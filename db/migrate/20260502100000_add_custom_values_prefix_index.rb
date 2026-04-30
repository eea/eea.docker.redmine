class AddCustomValuesPrefixIndex < ActiveRecord::Migration["#{Rails::VERSION::MAJOR}.#{Rails::VERSION::MINOR}".to_f]
  disable_ddl_transaction!

  def up
    unless index_name_exists?(:custom_values, "idx_custom_values_cf_id_value_prefix")
      add_index :custom_values, [:custom_field_id, :value], name: "idx_custom_values_cf_id_value_prefix", length: { value: 255 }
    end
  end

  def down
    remove_index :custom_values, name: "idx_custom_values_cf_id_value_prefix" if index_name_exists?(:custom_values, "idx_custom_values_cf_id_value_prefix")
  end
end