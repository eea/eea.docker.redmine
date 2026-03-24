class AddManualPrefixIdxJournalsOnJournalizedTypeJournalizedIdCreatedOn < ActiveRecord::Migration["#{Rails::VERSION::MAJOR}.#{Rails::VERSION::MINOR}".to_f]
  disable_ddl_transaction!

  TABLE_NAME = :journals
  INDEX_COLUMNS = [:journalized_type, :journalized_id, :created_on].freeze
  INDEX_NAME = "manual_prefix_idx_journals_on_journalized_type_journalized_id_created_on"

  def up
    unless table_exists?(TABLE_NAME)
      say "[manual_indexes] skip #{INDEX_NAME}: table #{TABLE_NAME} does not exist", true
      return
    end

    if index_exists?(TABLE_NAME, INDEX_COLUMNS, name: INDEX_NAME) || index_name_exists?(TABLE_NAME, INDEX_NAME)
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
