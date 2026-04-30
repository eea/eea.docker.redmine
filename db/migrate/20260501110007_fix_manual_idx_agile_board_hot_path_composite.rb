class FixManualIdxAgileBoardHotPathComposite < ActiveRecord::Migration["#{Rails::VERSION::MAJOR}.#{Rails::VERSION::MINOR}".to_f]
  disable_ddl_transaction!

  # This migration repairs the buggy index creation from 20260422124000_add_manual_idx_agile_board_hot_path
  # The bug: index_exists?(table, columns, name: name) returns TRUE on MySQL for partial matches
  # Fix: Use index_name_exists? (exact name match) + composite_index_exists? helper via information_schema.STATISTICS

  TABLE_NAME = :agile_data
  INDEX_COLUMNS = [:issue_id, :position]
  INDEX_NAME = "manual_idx_agile_data_on_issue_id_position"

  def up
    return unless table_exists?(TABLE_NAME)

    if index_name_exists?(TABLE_NAME, INDEX_NAME) && !composite_index_exists?(TABLE_NAME, INDEX_COLUMNS, INDEX_NAME)
      say "[manual_indexes] #{INDEX_NAME} has wrong structure, dropping malformed index", true
      remove_index TABLE_NAME, name: INDEX_NAME, if_exists: true
    end

    unless index_name_exists?(TABLE_NAME, INDEX_NAME)
      say "[manual_indexes] creating #{INDEX_NAME}", true
      if mysql_adapter?
        add_mysql_online_index(TABLE_NAME, INDEX_COLUMNS, INDEX_NAME)
      else
        add_index TABLE_NAME, INDEX_COLUMNS, name: INDEX_NAME
      end
    else
      say "[manual_indexes] skip #{INDEX_NAME}: already exists with correct structure", true
    end
  rescue StandardError => e
    say "[manual_indexes] soft-fail #{INDEX_NAME}: #{e.class}: #{e.message}", true
  end

  def down
    # No reverse needed for repair migration
  end

  private

  # Checks composite index existence via information_schema.STATISTICS
  # Returns true only if index exists with EXACT column sequence
  def composite_index_exists?(table, columns, name)
    return false unless index_name_exists?(table, name)

    sql = <<~SQL.squish
      SELECT COUNT(*) as count FROM information_schema.STATISTICS
      WHERE table_schema = DATABASE()
        AND table_name = #{connection.quote_table_name(table)}
        AND index_name = #{connection.quote_string(name)}
        AND SEQ_IN_INDEX = 1
    SQL

    result = connection.select_all(sql)
    return false if result.empty? || result.first["count"].to_i.zero?

    index_columns_sql = <<~SQL.squish
      SELECT COLUMN_NAME FROM information_schema.STATISTICS
      WHERE table_schema = DATABASE()
        AND table_name = #{connection.quote_table_name(table)}
        AND index_name = #{connection.quote_string(name)}
        AND SEQ_IN_INDEX IS NOT NULL
      ORDER BY SEQ_IN_INDEX
    SQL

    actual_columns = connection.select_all(index_columns_sql).pluck(:COLUMN_NAME)
    actual_columns == columns.map(&:to_s)
  end

  def mysql_adapter?
    connection.adapter_name.to_s.downcase.include?("mysql")
  end

  def add_mysql_online_index(table, columns, name)
    quoted_columns = columns.map { |column| connection.quote_column_name(column) }.join(", ")
    quoted_table = connection.quote_table_name(table)
    quoted_name = connection.quote_column_name(name)

    execute <<~SQL.squish
      ALTER TABLE #{quoted_table}
      ADD INDEX #{quoted_name} (#{quoted_columns}),
      ALGORITHM=INPLACE,
      LOCK=NONE
    SQL
  rescue ActiveRecord::StatementInvalid => e
    say "[manual_indexes] online DDL failed for #{name}: #{e.message}; retrying regular add_index", true
    add_index(table, columns, name: name)
  end
end
