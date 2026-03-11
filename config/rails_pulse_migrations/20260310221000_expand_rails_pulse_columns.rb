class ExpandRailsPulseColumns < ActiveRecord::Migration["#{Rails::VERSION::MAJOR}.#{Rails::VERSION::MINOR}".to_f]
  def up
    return unless table_exists?(:rails_pulse_queries) && table_exists?(:rails_pulse_operations)

    change_column :rails_pulse_queries, :normalized_sql, :text, null: false
    change_column :rails_pulse_operations, :label, :text, null: false
    change_column :rails_pulse_operations, :codebase_location, :text
  end

  def down
    return unless table_exists?(:rails_pulse_queries) && table_exists?(:rails_pulse_operations)

    change_column :rails_pulse_queries, :normalized_sql, :string, limit: 1000, null: false
    change_column :rails_pulse_operations, :label, :string, null: false
    change_column :rails_pulse_operations, :codebase_location, :string
  end
end
