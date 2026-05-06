# DuckGuard Extension Test Matrix

This matrix describes the permission combinations the extension should test after
`duckguard.protect(metadata_schema)` has been applied to a DuckLake metadata schema.

`none` means the user has no grant at that level. Catalog `has_usage` is assumed
for all non-catalog actions unless the row explicitly says otherwise.

| Schema permission | Table permission | DuckLake action | Result |
| --- | --- | --- | --- |
| none | none | Read schemas in catalog without `catalog_permissions.has_usage` | Denied |
| none | none | Read schemas in catalog with `catalog_permissions.has_usage` | Allowed |
| none | none | Create schema with `catalog_permissions.has_create` | Allowed |
| none | none | Create schema without `catalog_permissions.has_create` | Denied |
| none | none | Update/drop schema with `catalog_permissions.has_own` | Allowed |
| none | none | Update/drop schema without `catalog_permissions.has_own` | Denied |
| `has_usage` | none | List/read tables and views in schema | Allowed |
| none | none | List/read tables and views in schema | Denied |
| `has_create` | none | Create table or view in schema | Allowed |
| `has_usage` only | none | Create table or view in schema | Denied |
| `has_own` | none | Alter/drop table or view metadata in schema | Allowed |
| `has_usage` only | `has_own` | Alter/drop table or view metadata in schema | Denied |
| `has_all_table_select` | none | Select from any table in schema | Allowed |
| none | `has_select` | Select from granted table | Allowed |
| none | none | Select from table | Denied |
| `has_all_table_insert` | none | Insert rows into any table in schema | Allowed |
| none | `has_insert` | Insert rows into granted table | Allowed |
| none | `has_select` only | Insert rows into table | Denied |
| `has_all_table_select`, `has_all_table_update` | none | Update rows in any table in schema with a row predicate | Allowed |
| none | `has_select`, `has_update` | Update rows in granted table with a row predicate | Allowed |
| none | `has_insert` only | Update rows in table | Denied |
| `has_all_table_select`, `has_all_table_delete` | none | Delete rows from any table in schema with a row predicate | Allowed |
| none | `has_select`, `has_delete` | Delete rows from granted table with a row predicate | Allowed |
| none | `has_update` only | Delete rows from table | Denied |
| `has_own` | none | Add, rename, or drop columns on any table in schema | Allowed |
| none | `has_own` | Add, rename, or drop columns on owned table | Allowed |
| none | `has_update` only | Add, rename, or drop columns on table | Denied |
| none | `has_insert` only | Add, rename, or drop columns on table | Denied |
| none | `has_delete` only | Add, rename, or drop columns on table | Denied |
| `has_all_table_update` | none | Add, rename, or drop columns on table | Denied |
| `has_own` | none | Change table partition/sort metadata | Allowed |
| none | `has_own` | Change table partition/sort metadata | Denied |
| `has_usage` | `has_select` | Read table metadata, stats, files, and column metadata | Allowed |
| `has_usage` | none | Read table metadata, stats, files, and column metadata | Denied |
| `has_own` | none | Change table tags | Allowed |
| none | `has_own` | Change table tags | Denied |
| any | any | Superuser reads, creates, updates, or deletes protected metadata | Allowed |
