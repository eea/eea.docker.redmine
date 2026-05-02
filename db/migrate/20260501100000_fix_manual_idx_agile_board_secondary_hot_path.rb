# frozen_string_literal: true

# Migration to repair the broken index creation from 20260422132000.
#
# PROBLEM: The original migration used `index_exists?(:agile_data, [:issue_id, :position], name: ...)`
# which is buggy on MySQL. The MySQL adapter's index_exists? with columns returns TRUE for partial
# matches - it found "index_agile_data_on_issue_id" (single-column index on issue_id, which is the
# first column of the composite [:issue_id, :position]). This caused the migration to silently
# skip creating "manual_idx_agile_data_on_issue_id_position".
#
# FIX: Use only `index_name_exists?(:agile_data, "manual_idx_agile_data_on_issue_id_position")`
# which does an exact name match, avoiding the partial column match bug.
#
# This is safe to run multiple times (idempotent).

class FixManualIdxAgileBoardSecondaryHotPath < ActiveRecord::Migration["#{Rails::VERSION::MAJOR}.#{Rails::VERSION::MINOR}".to_f]
  disable_ddl_transaction!

  INDEX_NAME = "manual_idx_agile_data_on_issue_id_position"
  TABLE = :agile_data
  COLUMNS = [:issue_id, :position]

  def up
    unless table_exists?(TABLE)
      say "[manual_indexes] skip: #{TABLE} table does not exist yet (plugin not migrated)", true
      return
    end

    if composite_index_exists?(TABLE, COLUMNS)
      say "[manual_indexes] skip: composite index on #{TABLE} (#{COLUMNS.join(", ")}) already exists (any name)", true
      return
    end

    say "[manual_indexes] creating #{INDEX_NAME} on #{TABLE} (#{COLUMNS.join(", ")})", true

    if mysql_adapter?
      add_mysql_online_index
    else
      add_index(TABLE, COLUMNS, name: INDEX_NAME)
    end
  end

  def down
    # No-op: repair migration, no rollback needed
    say "[manual_indexes] down: no-op (repair migration)", true
  end

  private

  def composite_index_exists?(table, columns)
    return false unless mysql_adapter?

    schema = connection.current_database
    # Use quote() for string literals in WHERE clause, not quote_table_name()
    # (quote_table_name returns backticks which MySQL misinterprets as identifiers in TABLE_NAME comparison)
    quoted_table = connection.quote(table.to_s)
    col_list = columns.map { |c| connection.quote(c) }.join(",")

    result = select_all <<~SQL.squish, 'Check composite index'
      SELECT INDEX_NAME, GROUP_CONCAT(COLUMN_NAME ORDER BY SEQ_IN_INDEX) AS col_list
      FROM information_schema.STATISTICS
      WHERE TABLE_SCHEMA = #{connection.quote(schema)}
        AND TABLE_NAME = #{quoted_table}
        AND COLUMN_NAME IN (#{col_list})
        AND SEQ_IN_INDEX BETWEEN 1 AND #{columns.size}
      GROUP BY INDEX_NAME
      HAVING col_list = #{connection.quote(columns.join(","))}
    SQL

    result.any?
  rescue ActiveRecord::StatementInvalid
    false
  end

  def mysql_adapter?
    connection.adapter_name.to_s.downcase.include?("mysql")
  end

  def add_mysql_online_index
    quoted_columns = COLUMNS.map { |col| connection.quote_column_name(col) }.join(", ")
    quoted_table = connection.quote_table_name(TABLE)
    quoted_name = connection.quote_column_name(INDEX_NAME)

    execute <<~SQL.squish
      ALTER TABLE #{quoted_table}
      ADD INDEX #{quoted_name} (#{quoted_columns}),
      ALGORITHM=INPLACE,
      LOCK=NONE
    SQL
  rescue ActiveRecord::StatementInvalid => e
    say "[manual_indexes] online DDL failed for #{INDEX_NAME}: #{e.message}; retrying regular add_index", true
    add_index(TABLE, COLUMNS, name: INDEX_NAME)
  end
end