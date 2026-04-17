class AddManualIdxIssuesListHotPath < ActiveRecord::Migration["#{Rails::VERSION::MAJOR}.#{Rails::VERSION::MINOR}".to_f]
  disable_ddl_transaction!

  INDEX_DEFINITIONS = [
    {
      table: :issues,
      columns: [:status_id, :project_id, :id],
      name: "manual_idx_issues_on_status_project_id_id"
    },
    {
      table: :issues,
      columns: [:status_id, :id],
      name: "manual_idx_issues_on_status_id_id"
    },
    {
      table: :agile_colors,
      columns: [:container_type, :container_id],
      name: "manual_idx_agile_colors_on_container_type_container_id"
    }
  ].freeze

  def up
    INDEX_DEFINITIONS.each { |definition| create_index_soft(definition) }
  end

  def down
    INDEX_DEFINITIONS.each do |definition|
      remove_index definition[:table], name: definition[:name], if_exists: true
    end
  end

  private

  def create_index_soft(definition)
    table = definition[:table]
    columns = definition[:columns]
    name = definition[:name]

    unless table_exists?(table)
      say "[manual_indexes] skip #{name}: table #{table} does not exist", true
      return
    end

    if index_exists?(table, columns, name: name) || index_name_exists?(table, name)
      say "[manual_indexes] skip #{name}: already exists", true
      return
    end

    add_index_with_fallback(table, columns, name)
    say "[manual_indexes] created #{name}", true
  rescue StandardError => e
    say "[manual_indexes] soft-fail #{name}: #{e.class}: #{e.message}", true
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
