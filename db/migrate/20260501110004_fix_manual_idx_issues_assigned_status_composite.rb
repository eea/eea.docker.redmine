class FixManualIdxIssuesAssignedStatusComposite < ActiveRecord::Migration["#{Rails::VERSION::MAJOR}.#{Rails::VERSION::MINOR}".to_f]
  disable_ddl_transaction!

  TABLE_NAME = :issues
  INDEX_COLUMNS = [:assigned_to_id, :status_id, :tracker_id].freeze
  INDEX_NAME = "manual_idx_issues_assigned_status_tracker_id"

  def up
    unless table_exists?(TABLE_NAME)
      say "[manual_indexes] skip #{INDEX_NAME}: table #{TABLE_NAME} does not exist", true
      return
    end

    if index_name_exists?(TABLE_NAME, INDEX_NAME) || composite_index_exists?(TABLE_NAME, INDEX_COLUMNS)
      say "[manual_indexes] skip #{INDEX_NAME}: already exists", true
      return
    end

    add_index_with_fallback
    say "[manual_indexes] created #{INDEX_NAME}", true
  rescue StandardError => e
    say "[manual_indexes] soft-fail #{INDEX_NAME}: #{e.class}: #{e.message}", true
  end

  def down
    remove_index TABLE_NAME, name: INDEX_NAME, if_exists: true
  end

  private

  def composite_index_exists?(table, columns)
    return false unless mysql_adapter?

    quoted_table = connection.quote_table_name(table)
    columns_list = columns.map { |c| connection.quote_column_name(c) }.sort.join(", ")

    result = exec_query(<<~SQL.squish)
      SELECT 1 FROM information_schema.STATISTICS
      WHERE TABLE_SCHEMA = DATABASE()
        AND TABLE_NAME = #{quoted_table}
        AND INDEX_NAME = #{connection.quote_column_name(INDEX_NAME)}
      GROUP BY INDEX_NAME
      HAVING GROUP_CONCAT(CAST(SEQ_IN_INDEX AS CHAR) ORDER BY SEQ_IN_INDEX SEPARATOR ',') =
             (SELECT GROUP_CONCAT(CAST(SEQ_IN_INDEX AS CHAR) ORDER BY SEQ_IN_INDEX SEPARATOR ',')
              FROM information_schema.STATISTICS
              WHERE TABLE_SCHEMA = DATABASE()
                AND TABLE_NAME = #{quoted_table}
                AND COLUMN_NAME IN (#{columns.map { |c| connection.quote(c.to_s) }.join(", ")})
                AND SEQ_IN_INDEX = 1)
    SQL

    result.any?
  rescue ActiveRecord::StatementInvalid
    false
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
