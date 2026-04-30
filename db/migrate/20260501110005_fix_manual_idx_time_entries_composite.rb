class FixManualIdxTimeEntriesComposite < ActiveRecord::Migration["#{Rails::VERSION::MAJOR}.#{Rails::VERSION::MINOR}".to_f]
  disable_ddl_transaction!

  TABLE_NAME = :time_entries
  INDEX_COLUMNS = [:project_id, :user_id, :activity_id, :issue_id]
  INDEX_NAME = "manual_idx_time_entries_project_user_activity_issue_id"

  def up
    unless table_exists?(TABLE_NAME)
      say "[manual_indexes] skip #{INDEX_NAME}: table #{TABLE_NAME} does not exist", true
      return
    end

    if index_name_exists?(TABLE_NAME, INDEX_NAME) && composite_index_exists?(TABLE_NAME, INDEX_COLUMNS, INDEX_NAME)
      say "[manual_indexes] skip #{INDEX_NAME}: already exists", true
      return
    end

    unless index_name_exists?(TABLE_NAME, INDEX_NAME)
      say "[manual_indexes] #{INDEX_NAME}: missing from DB, creating", true
      add_index_with_fallback
      say "[manual_indexes] created #{INDEX_NAME}", true
    else
      say "[manual_indexes] #{INDEX_NAME}: name exists but columns mismatch, dropping and recreating", true
      remove_index TABLE_NAME, name: INDEX_NAME, if_exists: true
      add_index_with_fallback
      say "[manual_indexes] recreated #{INDEX_NAME}", true
    end
  rescue StandardError => e
    say "[manual_indexes] soft-fail #{INDEX_NAME}: #{e.class}: #{e.message}", true
  end

  def down
    remove_index TABLE_NAME, name: INDEX_NAME, if_exists: true
  end

  private

  def composite_index_exists?(table, columns, index_name)
    return false unless index_name_exists?(table, index_name)

    quoted_table = connection.quote_table_name(table)
    quoted_name = connection.quote_column_name(index_name)

    result = exec_query <<~SQL.squish, "SCHEMA"
      SELECT COUNT(*) AS count
      FROM information_schema.STATISTICS
      WHERE TABLE_SCHEMA = DATABASE()
        AND TABLE_NAME = #{quoted_table}
        AND INDEX_NAME = #{quoted_name}
        AND SEQ_IN_INDEX = 1
    SQL

    row = result.first
    return false unless row

    index_count = row["count"].to_i
    return false if index_count == 0

    columns.each_with_index do |column, seq|
      seq_in_index = seq + 1
      col_result = exec_query <<~SQL.squish, "SCHEMA"
        SELECT COLUMN_NAME
        FROM information_schema.STATISTICS
        WHERE TABLE_SCHEMA = DATABASE()
          AND TABLE_NAME = #{quoted_table}
          AND INDEX_NAME = #{quoted_name}
          AND SEQ_IN_INDEX = #{seq_in_index}
      SQL

      return false if col_result.empty?

      actual_column = col_result.first["COLUMN_NAME"]
      expected_column = connection.quote_column_name(column).gsub("`", "")
      return false if actual_column != expected_column
    end

    final_check = exec_query <<~SQL.squish, "SCHEMA"
      SELECT COUNT(*) AS total_columns
      FROM information_schema.STATISTICS
      WHERE TABLE_SCHEMA = DATABASE()
        AND TABLE_NAME = #{quoted_table}
        AND INDEX_NAME = #{quoted_name}
    SQL

    final_check.first["total_columns"].to_i == columns.size
  end

  def add_index_with_fallback
    if mysql_adapter?
      add_mysql_online_index
    else
      add_index(TABLE_NAME, INDEX_COLUMNS, name: INDEX_NAME)
    end
  end

  def mysql_adapter?
    connection.adapter_name.to_s.downcase.include?("mysql")
  end

  def add_mysql_online_index
    quoted_columns = INDEX_COLUMNS.map { |column| connection.quote_column_name(column) }.join(", ")
    quoted_table = connection.quote_table_name(TABLE_NAME)
    quoted_name = connection.quote_column_name(INDEX_NAME)

    execute <<~SQL.squish
      ALTER TABLE #{quoted_table}
      ADD INDEX #{quoted_name} (#{quoted_columns}),
      ALGORITHM=INPLACE,
      LOCK=NONE
    SQL
  rescue ActiveRecord::StatementInvalid => e
    say "[manual_indexes] online DDL failed for #{INDEX_NAME}: #{e.message}; retrying regular add_index", true
    add_index(TABLE_NAME, INDEX_COLUMNS, name: INDEX_NAME)
  end
end
