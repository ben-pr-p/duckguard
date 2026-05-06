# DuckGuard

DuckGuard is a simple security layer for DuckLake that gives DuckLake catalog, schema, and table level permissions
similar to PostgreSQL. It's not a service or proxy layer, but a big SQL script that you run on your database.

## How It Works

DuckGuard installs row-level security policies on DuckLake metadata tables that enforce permission checks before allowing access to any data.

It installs *one* set of row-level security policies *per-schema* (per catalog) that reference data internal tables. Then, permissions can be
changed by manipulating those data tables.

## Usage

```bash
psql "$CONNECTION_STRING" -f duckguard.sql
```

For each DuckLake catalog that you want to guard, run:
```sql
SELECT duckguard.protect('ducklake_metadata');
```

Now, you just need to manipulate the internal permission tables to adjust DuckLake permissions. DuckGuard generates
the PostgreSQL role name in `users.pg_user_name`; create a matching login role after inserting the user:
```sql
-- Create DuckGuard users. pg_user_name is generated automatically.
-- DuckGuard checks current_user against users.pg_user_name.
INSERT INTO duckguard.users (email)
VALUES
  ('analytics_reader@example.com'),
  ('analytics_writer@example.com'),
  ('schema_owner@example.com')
ON CONFLICT (email) DO UPDATE
SET email = EXCLUDED.email
RETURNING id, pg_user_name, email;

-- Create the resulting PostgreSQL login role with the generated pg_user_name.
CREATE ROLE uabc123generated LOGIN PASSWORD 'replace-with-a-long-random-password';

-- Let the role use a DuckLake catalog. The object name is the metadata schema
-- passed to duckguard.protect().
SELECT duckguard.set_catalog_permission(
  'analytics_reader@example.com',
  'ducklake_metadata',
  'usage'
);

-- Grant USAGE on one DuckLake schema.
SELECT duckguard.set_schema_permission(
  'analytics_reader@example.com',
  'ducklake_metadata.main',
  'usage'
);

-- Grant SELECT on every current and future table in that schema.
SELECT duckguard.set_schema_permission(
  'analytics_reader@example.com',
  'ducklake_metadata.main',
  'all_table_select'
);

-- Grant SELECT on one table only.
SELECT duckguard.set_table_permission(
  'analytics_reader@example.com',
  'ducklake_metadata.main.events',
  'select'
);

-- Grant table DML permissions. Predicate-based UPDATE/DELETE also need SELECT
-- so DuckLake can read the rows being matched.
SELECT duckguard.set_table_permission(
  'analytics_writer@example.com',
  'ducklake_metadata.main.events',
  'select'
);
SELECT duckguard.set_table_permission(
  'analytics_writer@example.com',
  'ducklake_metadata.main.events',
  'insert'
);
SELECT duckguard.set_table_permission(
  'analytics_writer@example.com',
  'ducklake_metadata.main.events',
  'update'
);
SELECT duckguard.set_table_permission(
  'analytics_writer@example.com',
  'ducklake_metadata.main.events',
  'delete'
);

-- Grant ownership-like schema powers: create/drop/alter tables in a schema.
SELECT duckguard.set_schema_permission(
  'schema_owner@example.com',
  'ducklake_metadata.main',
  'usage'
);
SELECT duckguard.set_schema_permission(
  'schema_owner@example.com',
  'ducklake_metadata.main',
  'create'
);
SELECT duckguard.set_schema_permission(
  'schema_owner@example.com',
  'ducklake_metadata.main',
  'own'
);

-- Revoke a table grant by clearing flags or deleting the row.
UPDATE duckguard.table_permissions
SET has_select = false,
    has_insert = false,
    has_update = false,
    has_delete = false,
    has_own = false
WHERE user_id = (
  SELECT id FROM duckguard.users WHERE email = 'analytics_reader@example.com'
)
  AND catalog_id = 'ducklake_metadata';

```

## Caveats

This provides a metadata ONLY level of permission enforcement. A user may still have access to the underlying data files.

If a user has read and/or write access to a bucket where all data files are stored, this does not provide meaningful security at all.

There are a few limited scenarios where this security is meaningful:
- **Read-only users with ListObjects disabled**: DuckLake parquet uuid's are basically unguessable. If a user only has object store read access but no ListObjects permission, they can only access specific objects if they know the exact key, which this system will prevent them from discovering.
- **Read-write users with path permissions enforced**: Some object stores support path-based access control. This allows you to restrict write operations to specific prefixes or directories within the bucket. This project does *NOT* provide a method of synchronizing those credentials, and not 
all S3 backends support those per key restrictions.
