class FixManualIdxUsersComposite < ActiveRecord::Migration["#{Rails::VERSION::MAJOR}.#{Rails::VERSION::MINOR}".to_f]
  disable_ddl_transaction!

  TABLE_NAME = :users
  INDEX_COLUMNS = [:type, :lastname, :id].freeze
  INDEX_NAME = "manual_prefix_idx_users_on_type_lastname_id"

  def up
    unless table_exists?(TABLE_NAME)
      say "[manual_indexes] skip #{INDEX_NAME}: table #{TABLE_NAME} does not exist", true
      return
    end

    # Use exact index_name_exists? only (avoid MySQL partial match bug)
    # AND composite_index_exists? to verify exact column match via information_schema
    if index_name_exists?(TABLE_NAME, INDEX_NAME) && composite_index_exists?(TABLE_NAME, INDEX_COLUMNS, INDEX_NAME)
      say "[manual_indexes] skip #{INDEX_NAME}: already exists with exact columns", true
      return
    end

    # If index exists but with wrong columns, remove it first
    if index_name_exists?(TABLE_NAME, INDEX_NAME)
      say "[manual_indexes] removing malformed #{INDEX_NAME}", true
      remove_index TABLE_NAME, name: INDEX_NAME, if_exists: true
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

  # Checks composite index exists with exact column match via information_schema.STATISTICS
  # Avoids MySQL index_exists? partial match bug
  def composite_index_exists?(table, columns, index_name)
    return false unless index_name_exists?(table, index_name)

    quoted_table = connection.quote_table_name(table)
    quoted_name = connection.quote_column_name(index_name)

    result = execute <<~SQL.squish
      SELECT COUNT(*) FROM information_schema.STATISTICS
      WHERE TABLE_SCHEMA = DATABASE()
        AND TABLE_NAME = #{quoted_table}
        AND INDEX_NAME = #{quoted_name}
        AND SEQ_IN_INDEX = #{columns.size}
    SQL

    count = result.first["COUNT(*)"] rescue 0
    count > 0
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
