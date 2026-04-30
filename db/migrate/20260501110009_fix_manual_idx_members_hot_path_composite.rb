class FixManualIdxMembersHotPathComposite < ActiveRecord::Migration["#{Rails::VERSION::MAJOR}.#{Rails::VERSION::MINOR}".to_f]
  disable_ddl_transaction!

  def up
    fix_index_definitions.each do |definition|
      repair_index(definition)
    end
  end

  def down
    # No-op: the original migration's down is safe to run as-is
  end

  private

  def fix_index_definitions
    [
      {
        table: :members,
        columns: [:project_id, :id],
        name: "manual_idx_members_query_hot_path"
      }
    ].freeze
  end

  def repair_index(definition)
    table = definition[:table]
    columns = definition[:columns]
    name = definition[:name]

    unless table_exists?(table)
      say "[manual_indexes] skip #{name}: table #{table} does not exist", true
      return
    end

    # Use index_name_exists? for exact name match only
    unless index_name_exists?(table, name)
      say "[manual_indexes] skip #{name}: does not exist", true
      return
    end

    # Verify it's a composite index on the correct columns via information_schema
    if composite_index_exists?(table, columns, name)
      say "[manual_indexes] skip #{name}: already correct", true
      return
    end

    remove_index table, name: name, if_exists: true
    add_index_with_fallback(table, columns, name)
    say "[manual_indexes] repaired #{name}", true
  rescue StandardError => e
    say "[manual_indexes] soft-fail #{name}: #{e.class}: #{e.message}", true
  end

  def composite_index_exists?(table, columns, name)
    scope = ::ActiveRecord::Base.connection
    table_name = scope.quoted_table_name(table)

    result = scope.execute <<~SQL.squish
      SELECT COUNT(*) FROM information_schema.STATISTICS
      WHERE TABLE_SCHEMA = DATABASE()
        AND TABLE_NAME = #{table_name}
        AND INDEX_NAME = #{scope.quote(name)}
        AND SEQ_IN_INDEX IN (#{columns.map { |c| scope.quote(columns.index(c) + 1) }.join(", ")})
      GROUP BY INDEX_NAME
      HAVING COUNT(*) = #{columns.length}
    SQL

    result.to_a.length == 1
  end

  def add_index_with_fallback(table, columns, name)
    if mysql_adapter?
      add_mysql_online_index(table, columns, name)
    else
      add_index(table, columns, name: name)
    end
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
