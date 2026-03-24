#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 2 || $# -gt 3 ]]; then
  echo "Usage: $0 <table_name> <col1,col2,...> [index_name]"
  echo "Example: $0 journal_details journal_id,prop_key manual_prefix_idx_journal_details_on_journal_id_prop_key"
  exit 1
fi

TABLE_NAME="$1"
COLUMNS_CSV="$2"
CUSTOM_INDEX_NAME="${3:-}"

if [[ -z "${TABLE_NAME}" || -z "${COLUMNS_CSV}" ]]; then
  echo "table_name and columns are required"
  exit 1
fi

IFS=',' read -r -a COLUMNS <<< "${COLUMNS_CSV}"
if [[ ${#COLUMNS[@]} -eq 0 ]]; then
  echo "At least one column is required"
  exit 1
fi

for i in "${!COLUMNS[@]}"; do
  COLUMNS[$i]="$(echo "${COLUMNS[$i]}" | xargs)"
  if [[ -z "${COLUMNS[$i]}" ]]; then
    echo "Empty column names are not allowed"
    exit 1
  fi
done

DEFAULT_INDEX_NAME="manual_prefix_idx_${TABLE_NAME}_on_$(IFS=_; echo "${COLUMNS[*]}")"
INDEX_NAME="${CUSTOM_INDEX_NAME:-$DEFAULT_INDEX_NAME}"

timestamp="$(date +"%Y%m%d%H%M%S")"
filename="${timestamp}_add_${INDEX_NAME}.rb"
migration_dir="db/migrate"
path="${migration_dir}/${filename}"

camelize() {
  echo "$1" | sed -E 's/[^a-zA-Z0-9]+/ /g' | awk '{for (i=1; i<=NF; i++) printf toupper(substr($i,1,1)) tolower(substr($i,2));}'
}

class_name="Add$(camelize "${INDEX_NAME}")"
columns_ruby=""
for col in "${COLUMNS[@]}"; do
  if [[ -n "${columns_ruby}" ]]; then
    columns_ruby="${columns_ruby}, "
  fi
  columns_ruby="${columns_ruby}:$col"
done

mkdir -p "${migration_dir}"

cat > "${path}" <<EOF
class ${class_name} < ActiveRecord::Migration["#{Rails::VERSION::MAJOR}.#{Rails::VERSION::MINOR}".to_f]
  disable_ddl_transaction!

  TABLE_NAME = :${TABLE_NAME}
  INDEX_COLUMNS = [${columns_ruby}].freeze
  INDEX_NAME = "${INDEX_NAME}"

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
EOF

echo "Generated ${path}"
