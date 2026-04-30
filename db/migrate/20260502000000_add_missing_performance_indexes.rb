class AddMissingPerformanceIndexes < ActiveRecord::Migration["#{Rails::VERSION::MAJOR}.#{Rails::VERSION::MINOR}".to_f]
  disable_ddl_transaction!

  INDEXES = [
    { table: :issues, columns: [:project_id, :status_id], name: "idx_issues_project_id_status_id" },
    { table: :issues, columns: [:project_id, :assigned_to_id], name: "idx_issues_project_id_assigned_to_id" },
    { table: :issues, columns: [:parent_id], name: "idx_issues_parent_id" },
    { table: :projects, columns: [:parent_id], name: "idx_projects_parent_id" },
    { table: :time_entries, columns: [:issue_id, :spent_on], name: "idx_time_entries_issue_id_spent_on" },
    { table: :custom_values, columns: [:custom_field_id, :value], name: "idx_custom_values_custom_field_id_value" },
    { table: :wiki_pages, columns: [:wiki_id, :title], name: "idx_wiki_pages_wiki_id_title" },
    { table: :wiki_links, columns: [:to_page_title], name: "idx_wiki_links_to_page_title" },
    { table: :wiki_pages, columns: [:title], name: "idx_wiki_pages_title" }
  ].freeze

  def up
    INDEXES.each do |index|
      create_index_if_missing(index[:table], index[:columns], index[:name])
    end
  end

  def down
    INDEXES.each do |index|
      remove_index index[:table], name: index[:name], if_exists: true
    end
  end

  private

  def create_index_if_missing(table, columns, name)
    unless table_exists?(table)
      say "[manual_indexes] skip #{name}: table #{table} does not exist", true
      return
    end

    if index_name_exists?(table, name)
      say "[manual_indexes] skip #{name}: already exists (by name)", true
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

  # Checks if any index covers the given columns (in order, all columns).
  # Uses information_schema.STATISTICS to avoid MySQL index_exists? false positives.
  def composite_index_exists?(table, columns)
    return false unless columns.present?

    schema = connection.select_all <<~SQL.squish
      SELECT NONUNIQUE INDEX_NAME
      FROM information_schema.STATISTICS
      WHERE TABLE_SCHEMA = DATABASE()
        AND TABLE_NAME = #{connection.quote_table_name(table)}
        AND SEQ_IN_INDEX = 1
    SQL

    schema.each do |row|
      index_name = row["INDEX_NAME"]
      index_columns = connection.select_values <<~SQL.squish
        SELECT COLUMN_NAME
        FROM information_schema.STATISTICS
        WHERE TABLE_SCHEMA = DATABASE()
          AND TABLE_NAME = #{connection.quote_table_name(table)}
          AND INDEX_NAME = #{connection.quote(index_name)}
        ORDER BY SEQ_IN_INDEX ASC
      SQL

      if index_columns == columns.map(&:to_s)
        return true
      end
    end

    false
  end
end
