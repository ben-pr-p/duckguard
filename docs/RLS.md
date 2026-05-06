# Row-Level Security (RLS)

This document describes how DuckGuard leverages row-level security to give
DuckLake catalog, schema, and table level security.

First, we assume that there is a schema called `duckguard` for internal use.

This schema contains the following tables:

- `users (id, pg_user_name, email, is_superuser)`: Stores user information
- `catalog_permissions (user_id, catalog_id, has_create, has_usage, has_own)`: Defines which users have access to which catalogs
- `schema_permissions (user_id, catalog_id, schema_id, has_create, has_usage, has_own, has_all_table_select, has_all_table_insert, has_all_table_update, has_all_table_delete)`: Defines which users have access to which schemas and default table privileges across each schema
- `table_permissions (user_id, catalog_id, table_id, has_select, has_insert, has_update, has_delete, has_own)`: Defines which users have access to table rows and table ownership

The data in these tables is used in the evaluation of RLS policies on internal DuckLake tables inside
of DuckLake catalogs on other schemas (assuming a schema called `metadata` for now), and roughly maps
to the following PostgreSQL-style permissions:

| DuckGuard permission | PostgreSQL permission it mirrors | DuckLake metadata effect |
| --- | --- | --- |
| `catalog_permissions.has_create` | `CREATE` on database | Can create schemas in the catalog by inserting active rows into `metadata.ducklake_schema`. |
| `catalog_permissions.has_usage` | `CONNECT` on database plus catalog visibility | Can see and use the catalog enough to access otherwise authorized schemas and tables. |
| `catalog_permissions.has_own` | Database ownership | Can update destructive catalog-level metadata and drop schemas in the catalog. |
| `schema_permissions.has_create` | `CREATE` on schema | Can create relations in a schema by inserting active rows into `metadata.ducklake_table`, `metadata.ducklake_view`, and schema-scoped macro rows where `schema_id` matches. |
| `schema_permissions.has_usage` | `USAGE` on schema | Can see schema-scoped metadata and use otherwise authorized relations in the schema. |
| `schema_permissions.has_own` | Schema ownership | Can alter or drop schema-owned objects, including expiring relation metadata in the schema. |
| `schema_permissions.has_all_table_select` | `SELECT` on all tables in schema | Can read data from every table in the schema without a per-table `table_permissions.has_select` grant. |
| `schema_permissions.has_all_table_insert` | `INSERT` on all tables in schema | Can insert data into every table in the schema without a per-table `table_permissions.has_insert` grant. |
| `schema_permissions.has_all_table_update` | `UPDATE` on all tables in schema | Can update data in every table in the schema without a per-table `table_permissions.has_update` grant. |
| `schema_permissions.has_all_table_delete` | `DELETE` on all tables in schema | Can delete data from every table in the schema without a per-table `table_permissions.has_delete` grant. |
| `table_permissions.has_select` | `SELECT` on table | Can read table data and supporting metadata for the table, including columns, data files, delete files, partition/sort metadata, table stats, column stats, file stats, tags, mappings, and inlined data. |
| `table_permissions.has_insert` | `INSERT` on table | Can add table data by inserting active rows into `metadata.ducklake_data_file`, `metadata.ducklake_inlined_data_*`, and related file, partition value, and stats tables for the table. |
| `table_permissions.has_update` | `UPDATE` on table | Can replace table data by inserting new active metadata rows and expiring old rows for the table. Column and table metadata changes still require ownership. |
| `table_permissions.has_delete` | `DELETE` on table | Can delete table data by writing delete-file metadata, expiring data-file or inlined-data rows, and scheduling physical files for deletion for the table. |
| `table_permissions.has_own` | Table ownership | Can alter table-owned metadata, including columns, column tags, and column mappings. |

For RLS policy purposes, internal DuckLake metadata tables can be grouped as follows:

| Metadata table | Permission check |
| --- | --- |
| `metadata.ducklake_schema` | `catalog_permissions.has_create` for inserts; `catalog_permissions.has_own` for updates, deletes, or expiry updates; visibility requires `catalog_permissions.has_usage`. |
| `metadata.ducklake_table` | `schema_permissions.has_create` for inserts; `schema_permissions.has_usage` for selects; `schema_permissions.has_own` for updates, deletes, or expiry updates. |
| `metadata.ducklake_view` | Same as `metadata.ducklake_table`, scoped by `schema_id`. |
| `metadata.ducklake_macro`, `metadata.ducklake_macro_impl`, `metadata.ducklake_macro_parameters` | Schema-level permissions, scoped through `ducklake_macro.schema_id`; implementation and parameter rows inherit the parent macro permission. |
| `metadata.ducklake_column`, `metadata.ducklake_column_tag`, `metadata.ducklake_column_mapping`, `metadata.ducklake_name_mapping` | `table_permissions.has_select` or `schema_permissions.has_all_table_select` for reads; `table_permissions.has_own` or `schema_permissions.has_own` for column and mapping changes, scoped through `table_id` or through a parent column/mapping tied to a table. |
| `metadata.ducklake_partition_info`, `metadata.ducklake_partition_column`, `metadata.ducklake_sort_info`, `metadata.ducklake_sort_expression` | `table_permissions.has_select` or `schema_permissions.has_all_table_select` for reads; `schema_permissions.has_own` for partition or sort changes, scoped through `table_id`; sort expression rows inherit the parent sort info permission. |
| `metadata.ducklake_data_file`, `metadata.ducklake_delete_file`, `metadata.ducklake_files_scheduled_for_deletion` | Table DML permissions; reads require `table_permissions.has_select` or `schema_permissions.has_all_table_select`; inserts into data-file metadata require `table_permissions.has_insert` or `schema_permissions.has_all_table_insert`; updates require `table_permissions.has_update` or `schema_permissions.has_all_table_update`; delete-file or scheduled-deletion writes require `table_permissions.has_delete` or `schema_permissions.has_all_table_delete`. |
| `metadata.ducklake_file_column_stats`, `metadata.ducklake_file_variant_stats`, `metadata.ducklake_file_partition_value` | Reads require `table_permissions.has_select` or `schema_permissions.has_all_table_select`; writes use the same table insert, update, or delete permission as the file metadata write that produced the rows, scoped through `table_id` or the referenced `data_file_id`. |
| `metadata.ducklake_table_stats`, `metadata.ducklake_table_column_stats` | Reads require `table_permissions.has_select` or `schema_permissions.has_all_table_select`; writes use the same table insert, update, or delete permission as the data rewrite that produced the rows, scoped through `table_id`. |
| `metadata.ducklake_tag` | `table_permissions.has_select` or `schema_permissions.has_all_table_select` for table tag reads; `schema_permissions.has_usage` for schema tag reads; `schema_permissions.has_own` for tag changes, scoped through object id. |
| `metadata.ducklake_inlined_data_tables`, `metadata.ducklake_inlined_data_*` | Table DML permissions; reads require `table_permissions.has_select` or `schema_permissions.has_all_table_select`; generated inlined data rows inherit insert, update, or delete permission from the table mapped by `ducklake_inlined_data_tables`. |
| `metadata.ducklake_schema_versions`, `metadata.ducklake_snapshot`, `metadata.ducklake_metadata` | Catalog bookkeeping. Reads require `catalog_permissions.has_usage` and should expose only otherwise authorized schemas/tables; writes should be limited to the DuckLake engine or `catalog_permissions.has_own` because these rows are cross-object state rather than user-facing relations. |
| `metadata.ducklake_snapshot_changes` | Catalog bookkeeping plus semantic inline DML gate. Inline insert changes require insert permission, inline insert+delete changes require update permission, and inline delete-only changes require delete permission for the referenced table. |
