class EnsureRailsPulseSchemaCompatibility < ActiveRecord::Migration["#{Rails::VERSION::MAJOR}.#{Rails::VERSION::MINOR}".to_f]
  def up
    ensure_queries_hashed_sql!
    ensure_operations_job_run_id!
  end

  def down
    if table_exists?(:rails_pulse_operations)
      remove_index :rails_pulse_operations, name: "index_rails_pulse_operations_on_job_run_id", if_exists: true
      remove_column :rails_pulse_operations, :job_run_id, if_exists: true
    end

    if table_exists?(:rails_pulse_queries)
      remove_index :rails_pulse_queries, name: "index_rails_pulse_queries_on_hashed_sql", if_exists: true
      remove_column :rails_pulse_queries, :hashed_sql, if_exists: true
    end
  end

  private

  def ensure_queries_hashed_sql!
    return unless table_exists?(:rails_pulse_queries)

    unless column_exists?(:rails_pulse_queries, :hashed_sql)
      add_column :rails_pulse_queries, :hashed_sql, :string, limit: 32
    end

    execute <<~SQL.squish
      UPDATE rails_pulse_queries
      SET hashed_sql = MD5(COALESCE(normalized_sql, ''))
      WHERE hashed_sql IS NULL OR hashed_sql = ''
    SQL

    change_column_null :rails_pulse_queries, :hashed_sql, false
    change_column :rails_pulse_queries, :hashed_sql, :string, limit: 32, null: false

    add_index :rails_pulse_queries,
              :hashed_sql,
              unique: true,
              name: "index_rails_pulse_queries_on_hashed_sql",
              if_not_exists: true
  end

  def ensure_operations_job_run_id!
    return unless table_exists?(:rails_pulse_operations)

    add_column :rails_pulse_operations, :job_run_id, :bigint unless column_exists?(:rails_pulse_operations, :job_run_id)

    add_index :rails_pulse_operations,
              :job_run_id,
              name: "index_rails_pulse_operations_on_job_run_id",
              if_not_exists: true
  end
end
