CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE SCHEMA IF NOT EXISTS duckguard;

CREATE OR REPLACE FUNCTION duckguard.generate_pg_user_name()
RETURNS text
LANGUAGE sql
VOLATILE
AS $$
  SELECT 'u' || lower(substr(replace(gen_random_uuid()::text, '-', ''), 1, 15));
$$;

CREATE TABLE IF NOT EXISTS duckguard.users (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  pg_user_name text NOT NULL UNIQUE DEFAULT duckguard.generate_pg_user_name(),
  email text NOT NULL UNIQUE,
  is_superuser boolean NOT NULL DEFAULT false
);

ALTER TABLE duckguard.users
  ADD COLUMN IF NOT EXISTS id uuid DEFAULT gen_random_uuid(),
  ADD COLUMN IF NOT EXISTS pg_user_name text DEFAULT duckguard.generate_pg_user_name(),
  ADD COLUMN IF NOT EXISTS email text,
  ADD COLUMN IF NOT EXISTS is_superuser boolean NOT NULL DEFAULT false;

CREATE TABLE IF NOT EXISTS duckguard.catalog_permissions (
  user_id uuid NOT NULL,
  catalog_id text NOT NULL,
  has_create boolean NOT NULL DEFAULT false,
  has_usage boolean NOT NULL DEFAULT false,
  has_own boolean NOT NULL DEFAULT false,
  PRIMARY KEY (user_id, catalog_id)
);

ALTER TABLE duckguard.catalog_permissions
  ADD COLUMN IF NOT EXISTS user_id uuid,
  ADD COLUMN IF NOT EXISTS catalog_id text,
  ADD COLUMN IF NOT EXISTS has_create boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS has_usage boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS has_own boolean NOT NULL DEFAULT false;

CREATE TABLE IF NOT EXISTS duckguard.schema_permissions (
  user_id uuid NOT NULL,
  catalog_id text NOT NULL,
  schema_id bigint NOT NULL,
  has_create boolean NOT NULL DEFAULT false,
  has_usage boolean NOT NULL DEFAULT false,
  has_own boolean NOT NULL DEFAULT false,
  has_all_table_select boolean NOT NULL DEFAULT false,
  has_all_table_insert boolean NOT NULL DEFAULT false,
  has_all_table_update boolean NOT NULL DEFAULT false,
  has_all_table_delete boolean NOT NULL DEFAULT false,
  PRIMARY KEY (user_id, catalog_id, schema_id)
);

ALTER TABLE duckguard.schema_permissions
  ADD COLUMN IF NOT EXISTS user_id uuid,
  ADD COLUMN IF NOT EXISTS catalog_id text,
  ADD COLUMN IF NOT EXISTS schema_id bigint,
  ADD COLUMN IF NOT EXISTS has_create boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS has_usage boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS has_own boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS has_all_table_select boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS has_all_table_insert boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS has_all_table_update boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS has_all_table_delete boolean NOT NULL DEFAULT false;

CREATE TABLE IF NOT EXISTS duckguard.table_permissions (
  user_id uuid NOT NULL,
  catalog_id text NOT NULL,
  table_id bigint NOT NULL,
  has_select boolean NOT NULL DEFAULT false,
  has_insert boolean NOT NULL DEFAULT false,
  has_update boolean NOT NULL DEFAULT false,
  has_delete boolean NOT NULL DEFAULT false,
  has_own boolean NOT NULL DEFAULT false,
  PRIMARY KEY (user_id, catalog_id, table_id)
);

ALTER TABLE duckguard.table_permissions
  ADD COLUMN IF NOT EXISTS user_id uuid,
  ADD COLUMN IF NOT EXISTS catalog_id text,
  ADD COLUMN IF NOT EXISTS table_id bigint,
  ADD COLUMN IF NOT EXISTS has_select boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS has_insert boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS has_update boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS has_delete boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS has_own boolean NOT NULL DEFAULT false;

ALTER TABLE duckguard.catalog_permissions
  DROP CONSTRAINT IF EXISTS catalog_permissions_user_id_fkey;

ALTER TABLE duckguard.schema_permissions
  DROP CONSTRAINT IF EXISTS schema_permissions_user_id_fkey;

ALTER TABLE duckguard.table_permissions
  DROP CONSTRAINT IF EXISTS table_permissions_user_id_fkey;

CREATE INDEX IF NOT EXISTS schema_permissions_catalog_schema_idx
  ON duckguard.schema_permissions (catalog_id, schema_id);

CREATE INDEX IF NOT EXISTS table_permissions_catalog_table_idx
  ON duckguard.table_permissions (catalog_id, table_id);

CREATE OR REPLACE FUNCTION duckguard.set_catalog_permission(
  email text,
  object_name text,
  permission text
)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  target_user_id uuid;
  normalized_permission text := lower(permission);
BEGIN
  IF normalized_permission NOT IN ('create', 'usage', 'own') THEN
    RAISE EXCEPTION 'unknown catalog permission: %', permission;
  END IF;

  SELECT u.id INTO target_user_id
  FROM duckguard.users AS u
  WHERE u.email = set_catalog_permission.email;

  IF target_user_id IS NULL THEN
    RAISE EXCEPTION 'unknown duckguard user email: %', email;
  END IF;

  INSERT INTO duckguard.catalog_permissions (
    user_id,
    catalog_id,
    has_create,
    has_usage,
    has_own
  )
  VALUES (
    target_user_id,
    object_name,
    normalized_permission = 'create',
    normalized_permission = 'usage',
    normalized_permission = 'own'
  )
  ON CONFLICT (user_id, catalog_id) DO UPDATE
  SET has_create = duckguard.catalog_permissions.has_create OR EXCLUDED.has_create,
      has_usage = duckguard.catalog_permissions.has_usage OR EXCLUDED.has_usage,
      has_own = duckguard.catalog_permissions.has_own OR EXCLUDED.has_own;
END;
$$;

CREATE OR REPLACE FUNCTION duckguard.set_schema_permission(
  email text,
  object_name text,
  permission text
)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  target_user_id uuid;
  target_catalog_id text;
  schema_name text;
  target_schema_id bigint;
  normalized_permission text := lower(permission);
  object_parts text[] := string_to_array(object_name, '.');
BEGIN
  IF array_length(object_parts, 1) != 2 THEN
    RAISE EXCEPTION 'schema object_name must be catalog.schema: %', object_name;
  END IF;

  IF normalized_permission NOT IN (
    'create',
    'usage',
    'own',
    'all_table_select',
    'all_table_insert',
    'all_table_update',
    'all_table_delete'
  ) THEN
    RAISE EXCEPTION 'unknown schema permission: %', permission;
  END IF;

  SELECT u.id INTO target_user_id
  FROM duckguard.users AS u
  WHERE u.email = set_schema_permission.email;

  IF target_user_id IS NULL THEN
    RAISE EXCEPTION 'unknown duckguard user email: %', email;
  END IF;

  target_catalog_id := object_parts[1];
  schema_name := object_parts[2];

  EXECUTE format(
    'SELECT schema_id FROM %I.ducklake_schema WHERE schema_name = $1 AND end_snapshot IS NULL',
    target_catalog_id
  )
  INTO target_schema_id
  USING schema_name;

  IF target_schema_id IS NULL THEN
    RAISE EXCEPTION 'unknown ducklake schema: %', object_name;
  END IF;

  INSERT INTO duckguard.schema_permissions (
    user_id,
    catalog_id,
    schema_id,
    has_create,
    has_usage,
    has_own,
    has_all_table_select,
    has_all_table_insert,
    has_all_table_update,
    has_all_table_delete
  )
  VALUES (
    target_user_id,
    target_catalog_id,
    target_schema_id,
    normalized_permission = 'create',
    normalized_permission = 'usage',
    normalized_permission = 'own',
    normalized_permission = 'all_table_select',
    normalized_permission = 'all_table_insert',
    normalized_permission = 'all_table_update',
    normalized_permission = 'all_table_delete'
  )
  ON CONFLICT (user_id, catalog_id, schema_id) DO UPDATE
  SET has_create = duckguard.schema_permissions.has_create OR EXCLUDED.has_create,
      has_usage = duckguard.schema_permissions.has_usage OR EXCLUDED.has_usage,
      has_own = duckguard.schema_permissions.has_own OR EXCLUDED.has_own,
      has_all_table_select = duckguard.schema_permissions.has_all_table_select OR EXCLUDED.has_all_table_select,
      has_all_table_insert = duckguard.schema_permissions.has_all_table_insert OR EXCLUDED.has_all_table_insert,
      has_all_table_update = duckguard.schema_permissions.has_all_table_update OR EXCLUDED.has_all_table_update,
      has_all_table_delete = duckguard.schema_permissions.has_all_table_delete OR EXCLUDED.has_all_table_delete;
END;
$$;

CREATE OR REPLACE FUNCTION duckguard.set_table_permission(
  email text,
  object_name text,
  permission text
)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  target_user_id uuid;
  target_catalog_id text;
  schema_name text;
  table_name text;
  target_table_id bigint;
  normalized_permission text := lower(permission);
  object_parts text[] := string_to_array(object_name, '.');
BEGIN
  IF array_length(object_parts, 1) != 3 THEN
    RAISE EXCEPTION 'table object_name must be catalog.schema.table: %', object_name;
  END IF;

  IF normalized_permission NOT IN ('select', 'insert', 'update', 'delete', 'own') THEN
    RAISE EXCEPTION 'unknown table permission: %', permission;
  END IF;

  SELECT u.id INTO target_user_id
  FROM duckguard.users AS u
  WHERE u.email = set_table_permission.email;

  IF target_user_id IS NULL THEN
    RAISE EXCEPTION 'unknown duckguard user email: %', email;
  END IF;

  target_catalog_id := object_parts[1];
  schema_name := object_parts[2];
  table_name := object_parts[3];

  EXECUTE format(
    $lookup$
      SELECT dt.table_id
      FROM %I.ducklake_table AS dt
      JOIN %I.ducklake_schema AS ds ON ds.schema_id = dt.schema_id
      WHERE ds.schema_name = $1
        AND ds.end_snapshot IS NULL
        AND dt.table_name = $2
        AND dt.end_snapshot IS NULL
    $lookup$,
    target_catalog_id,
    target_catalog_id
  )
  INTO target_table_id
  USING schema_name, table_name;

  IF target_table_id IS NULL THEN
    RAISE EXCEPTION 'unknown ducklake table: %', object_name;
  END IF;

  INSERT INTO duckguard.table_permissions (
    user_id,
    catalog_id,
    table_id,
    has_select,
    has_insert,
    has_update,
    has_delete,
    has_own
  )
  VALUES (
    target_user_id,
    target_catalog_id,
    target_table_id,
    normalized_permission = 'select',
    normalized_permission = 'insert',
    normalized_permission = 'update',
    normalized_permission = 'delete',
    normalized_permission = 'own'
  )
  ON CONFLICT (user_id, catalog_id, table_id) DO UPDATE
  SET has_select = duckguard.table_permissions.has_select OR EXCLUDED.has_select,
      has_insert = duckguard.table_permissions.has_insert OR EXCLUDED.has_insert,
      has_update = duckguard.table_permissions.has_update OR EXCLUDED.has_update,
      has_delete = duckguard.table_permissions.has_delete OR EXCLUDED.has_delete,
      has_own = duckguard.table_permissions.has_own OR EXCLUDED.has_own;
END;
$$;

CREATE OR REPLACE FUNCTION duckguard.user_has_catalog_permission(
  role_name text,
  catalog_id text,
  permission text
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM duckguard.users AS u
    WHERE u.pg_user_name = role_name
      AND u.is_superuser
  ) OR EXISTS (
    SELECT 1
    FROM duckguard.users AS u
    JOIN duckguard.catalog_permissions AS cp ON cp.user_id = u.id
    WHERE u.pg_user_name = role_name
      AND cp.catalog_id = user_has_catalog_permission.catalog_id
      AND CASE lower(user_has_catalog_permission.permission)
        WHEN 'create' THEN cp.has_create
        WHEN 'usage' THEN cp.has_usage
        WHEN 'own' THEN cp.has_own
        ELSE false
      END
  );
$$;

CREATE OR REPLACE FUNCTION duckguard.get_schema_ids_for_user_with_permission(
  role_name text,
  permission text
)
RETURNS SETOF bigint
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
AS $$
DECLARE
  normalized_permission text := lower(permission);
  permission_record record;
BEGIN
  IF normalized_permission NOT IN ('create', 'usage', 'own') THEN
    RAISE EXCEPTION 'unknown schema permission: %', permission;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM duckguard.users AS u
    WHERE u.pg_user_name = role_name
      AND u.is_superuser
  ) THEN
    FOR permission_record IN
      SELECT n.nspname AS catalog_id
      FROM pg_catalog.pg_class AS c
      JOIN pg_catalog.pg_namespace AS n ON n.oid = c.relnamespace
      WHERE c.relname = 'ducklake_schema'
        AND c.relkind IN ('r', 'p')
    LOOP
      RETURN QUERY EXECUTE format(
        'SELECT schema_id FROM %I.ducklake_schema',
        permission_record.catalog_id
      );
    END LOOP;

    RETURN;
  END IF;

  RETURN QUERY
    SELECT sp.schema_id
    FROM duckguard.users AS u
    JOIN duckguard.schema_permissions AS sp ON sp.user_id = u.id
    WHERE u.pg_user_name = role_name
      AND CASE normalized_permission
        WHEN 'create' THEN sp.has_create
        WHEN 'usage' THEN sp.has_usage
        WHEN 'own' THEN sp.has_own
      END;

  FOR permission_record IN
    SELECT cp.catalog_id
    FROM duckguard.users AS u
    JOIN duckguard.catalog_permissions AS cp ON cp.user_id = u.id
    WHERE u.pg_user_name = role_name
      AND pg_catalog.to_regclass(format('%I.ducklake_schema', cp.catalog_id)) IS NOT NULL
      AND CASE normalized_permission
        WHEN 'usage' THEN cp.has_usage
        WHEN 'own' THEN cp.has_own
        ELSE false
      END
  LOOP
    RETURN QUERY EXECUTE format(
      'SELECT schema_id FROM %I.ducklake_schema',
      permission_record.catalog_id
    );
  END LOOP;
END;
$$;

CREATE OR REPLACE FUNCTION duckguard.get_table_ids_for_user_with_permission(
  role_name text,
  permission text
)
RETURNS SETOF bigint
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
AS $$
DECLARE
  normalized_permission text := lower(permission);
  permission_record record;
BEGIN
  IF normalized_permission NOT IN ('select', 'insert', 'update', 'delete', 'own', 'create') THEN
    RAISE EXCEPTION 'unknown table permission: %', permission;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM duckguard.users AS u
    WHERE u.pg_user_name = role_name
      AND u.is_superuser
  ) THEN
    FOR permission_record IN
      SELECT n.nspname AS catalog_id
      FROM pg_catalog.pg_class AS c
      JOIN pg_catalog.pg_namespace AS n ON n.oid = c.relnamespace
      WHERE c.relname = 'ducklake_table'
        AND c.relkind IN ('r', 'p')
    LOOP
      RETURN QUERY EXECUTE format(
        'SELECT table_id FROM %I.ducklake_table',
        permission_record.catalog_id
      );
    END LOOP;

    RETURN;
  END IF;

  RETURN QUERY
    SELECT tp.table_id
    FROM duckguard.users AS u
    JOIN duckguard.table_permissions AS tp ON tp.user_id = u.id
    WHERE u.pg_user_name = role_name
      AND CASE normalized_permission
        WHEN 'select' THEN tp.has_select
        WHEN 'insert' THEN tp.has_insert
        WHEN 'update' THEN tp.has_update
        WHEN 'delete' THEN tp.has_delete
        WHEN 'own' THEN tp.has_own
        ELSE false
      END;

  FOR permission_record IN
    SELECT sp.catalog_id, sp.schema_id
    FROM duckguard.users AS u
    JOIN duckguard.schema_permissions AS sp ON sp.user_id = u.id
    WHERE u.pg_user_name = role_name
      AND pg_catalog.to_regclass(format('%I.ducklake_table', sp.catalog_id)) IS NOT NULL
      AND CASE normalized_permission
        WHEN 'select' THEN sp.has_all_table_select
        WHEN 'insert' THEN sp.has_all_table_insert
        WHEN 'update' THEN sp.has_all_table_update
        WHEN 'delete' THEN sp.has_all_table_delete
        WHEN 'own' THEN sp.has_own
        WHEN 'create' THEN sp.has_create
      END
  LOOP
    RETURN QUERY EXECUTE format(
      'SELECT table_id FROM %I.ducklake_table WHERE schema_id = $1',
      permission_record.catalog_id
    )
    USING permission_record.schema_id;
  END LOOP;
END;
$$;

CREATE OR REPLACE FUNCTION duckguard.protect(metadata_schema text)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  table_name text;
  inlined_record record;
  catalog text := metadata_schema;
BEGIN
  PERFORM set_config('search_path', metadata_schema, true);

  EXECUTE 'ALTER TABLE ducklake_schema ENABLE ROW LEVEL SECURITY';
  EXECUTE 'DROP POLICY IF EXISTS duckguard_select ON ducklake_schema';
  EXECUTE 'DROP POLICY IF EXISTS duckguard_insert ON ducklake_schema';
  EXECUTE 'DROP POLICY IF EXISTS duckguard_update ON ducklake_schema';
  EXECUTE 'DROP POLICY IF EXISTS duckguard_delete ON ducklake_schema';
  EXECUTE $policy$
    CREATE POLICY duckguard_select ON ducklake_schema
    FOR SELECT USING (
      schema_id IN (
        SELECT duckguard.get_schema_ids_for_user_with_permission(current_user, 'usage')
      )
    )
  $policy$;
  EXECUTE format($policy$
    CREATE POLICY duckguard_insert ON ducklake_schema
    FOR INSERT WITH CHECK (
      duckguard.user_has_catalog_permission(current_user, %L, 'create')
    )
  $policy$, catalog);
  EXECUTE $policy$
    CREATE POLICY duckguard_update ON ducklake_schema
    FOR UPDATE USING (
      schema_id IN (
        SELECT duckguard.get_schema_ids_for_user_with_permission(current_user, 'own')
      )
    )
  $policy$;
  EXECUTE $policy$
    CREATE POLICY duckguard_delete ON ducklake_schema
    FOR DELETE USING (
      schema_id IN (
        SELECT duckguard.get_schema_ids_for_user_with_permission(current_user, 'own')
      )
    )
  $policy$;

  FOREACH table_name IN ARRAY ARRAY['ducklake_table', 'ducklake_view'] LOOP
    EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', table_name);
    EXECUTE format('DROP POLICY IF EXISTS duckguard_select ON %I', table_name);
    EXECUTE format('DROP POLICY IF EXISTS duckguard_insert ON %I', table_name);
    EXECUTE format('DROP POLICY IF EXISTS duckguard_update ON %I', table_name);
    EXECUTE format('DROP POLICY IF EXISTS duckguard_delete ON %I', table_name);
    EXECUTE format($policy$
      CREATE POLICY duckguard_select ON %I
      FOR SELECT USING (
        schema_id IN (
          SELECT duckguard.get_schema_ids_for_user_with_permission(current_user, 'usage')
        )
      )
    $policy$, table_name);
    EXECUTE format($policy$
      CREATE POLICY duckguard_insert ON %I
      FOR INSERT WITH CHECK (
        schema_id IN (
          SELECT duckguard.get_schema_ids_for_user_with_permission(current_user, 'create')
        )
      )
    $policy$, table_name);
    EXECUTE format($policy$
      CREATE POLICY duckguard_update ON %I
      FOR UPDATE USING (
        schema_id IN (
          SELECT duckguard.get_schema_ids_for_user_with_permission(current_user, 'own')
        )
      )
    $policy$, table_name);
    EXECUTE format($policy$
      CREATE POLICY duckguard_delete ON %I
      FOR DELETE USING (
        schema_id IN (
          SELECT duckguard.get_schema_ids_for_user_with_permission(current_user, 'own')
        )
      )
    $policy$, table_name);
  END LOOP;

  FOREACH table_name IN ARRAY ARRAY[
    'ducklake_data_file',
    'ducklake_file_column_stats',
    'ducklake_file_partition_value',
    'ducklake_file_variant_stats'
  ] LOOP
    EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', table_name);
    EXECUTE format('DROP POLICY IF EXISTS duckguard_select ON %I', table_name);
    EXECUTE format('DROP POLICY IF EXISTS duckguard_insert ON %I', table_name);
    EXECUTE format('DROP POLICY IF EXISTS duckguard_update ON %I', table_name);
    EXECUTE format('DROP POLICY IF EXISTS duckguard_delete ON %I', table_name);
    EXECUTE format($policy$
      CREATE POLICY duckguard_select ON %I
      FOR SELECT USING (
        table_id IN (
          SELECT duckguard.get_table_ids_for_user_with_permission(current_user, 'select')
        )
      )
    $policy$, table_name);
    EXECUTE format($policy$
      CREATE POLICY duckguard_insert ON %I
      FOR INSERT WITH CHECK (
        table_id IN (
          SELECT duckguard.get_table_ids_for_user_with_permission(current_user, 'insert')
        )
      )
    $policy$, table_name);
    EXECUTE format($policy$
      CREATE POLICY duckguard_update ON %I
      FOR UPDATE USING (
        table_id IN (
          SELECT duckguard.get_table_ids_for_user_with_permission(current_user, 'update')
        )
      )
    $policy$, table_name);
    EXECUTE format($policy$
      CREATE POLICY duckguard_delete ON %I
      FOR DELETE USING (
        table_id IN (
          SELECT duckguard.get_table_ids_for_user_with_permission(current_user, 'delete')
        )
      )
    $policy$, table_name);
  END LOOP;

  FOREACH table_name IN ARRAY ARRAY[
    'ducklake_table_column_stats',
    'ducklake_table_stats'
  ] LOOP
    EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', table_name);
    EXECUTE format('DROP POLICY IF EXISTS duckguard_select ON %I', table_name);
    EXECUTE format('DROP POLICY IF EXISTS duckguard_insert ON %I', table_name);
    EXECUTE format('DROP POLICY IF EXISTS duckguard_update ON %I', table_name);
    EXECUTE format('DROP POLICY IF EXISTS duckguard_delete ON %I', table_name);
    EXECUTE format($policy$
      CREATE POLICY duckguard_select ON %I
      FOR SELECT USING (
        table_id IN (
          SELECT duckguard.get_table_ids_for_user_with_permission(current_user, 'select')
        )
      )
    $policy$, table_name);
    EXECUTE format($policy$
      CREATE POLICY duckguard_insert ON %I
      FOR INSERT WITH CHECK (
        table_id IN (SELECT duckguard.get_table_ids_for_user_with_permission(current_user, 'insert'))
        OR table_id IN (SELECT duckguard.get_table_ids_for_user_with_permission(current_user, 'update'))
        OR table_id IN (SELECT duckguard.get_table_ids_for_user_with_permission(current_user, 'delete'))
      )
    $policy$, table_name);
    EXECUTE format($policy$
      CREATE POLICY duckguard_update ON %I
      FOR UPDATE USING (
        table_id IN (SELECT duckguard.get_table_ids_for_user_with_permission(current_user, 'update'))
        OR table_id IN (SELECT duckguard.get_table_ids_for_user_with_permission(current_user, 'delete'))
      )
    $policy$, table_name);
    EXECUTE format($policy$
      CREATE POLICY duckguard_delete ON %I
      FOR DELETE USING (
        table_id IN (
          SELECT duckguard.get_table_ids_for_user_with_permission(current_user, 'delete')
        )
      )
    $policy$, table_name);
  END LOOP;

  EXECUTE 'ALTER TABLE ducklake_delete_file ENABLE ROW LEVEL SECURITY';
  EXECUTE 'DROP POLICY IF EXISTS duckguard_select ON ducklake_delete_file';
  EXECUTE 'DROP POLICY IF EXISTS duckguard_insert ON ducklake_delete_file';
  EXECUTE 'DROP POLICY IF EXISTS duckguard_update ON ducklake_delete_file';
  EXECUTE 'DROP POLICY IF EXISTS duckguard_delete ON ducklake_delete_file';
  EXECUTE $policy$
    CREATE POLICY duckguard_select ON ducklake_delete_file
    FOR SELECT USING (
      table_id IN (
        SELECT duckguard.get_table_ids_for_user_with_permission(current_user, 'select')
      )
    )
  $policy$;
  EXECUTE $policy$
    CREATE POLICY duckguard_insert ON ducklake_delete_file
    FOR INSERT WITH CHECK (
      table_id IN (SELECT duckguard.get_table_ids_for_user_with_permission(current_user, 'update'))
      OR table_id IN (SELECT duckguard.get_table_ids_for_user_with_permission(current_user, 'delete'))
    )
  $policy$;
  EXECUTE $policy$
    CREATE POLICY duckguard_update ON ducklake_delete_file
    FOR UPDATE USING (
      table_id IN (SELECT duckguard.get_table_ids_for_user_with_permission(current_user, 'update'))
      OR table_id IN (SELECT duckguard.get_table_ids_for_user_with_permission(current_user, 'delete'))
    )
  $policy$;
  EXECUTE $policy$
    CREATE POLICY duckguard_delete ON ducklake_delete_file
    FOR DELETE USING (
      table_id IN (
        SELECT duckguard.get_table_ids_for_user_with_permission(current_user, 'delete')
      )
    )
  $policy$;

  FOREACH table_name IN ARRAY ARRAY[
    'ducklake_partition_column',
    'ducklake_partition_info',
    'ducklake_sort_info'
  ] LOOP
    EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', table_name);
    EXECUTE format('DROP POLICY IF EXISTS duckguard_select ON %I', table_name);
    EXECUTE format('DROP POLICY IF EXISTS duckguard_insert ON %I', table_name);
    EXECUTE format('DROP POLICY IF EXISTS duckguard_update ON %I', table_name);
    EXECUTE format('DROP POLICY IF EXISTS duckguard_delete ON %I', table_name);
    EXECUTE format($policy$
      CREATE POLICY duckguard_select ON %I
      FOR SELECT USING (
        table_id IN (
          SELECT duckguard.get_table_ids_for_user_with_permission(current_user, 'select')
        )
      )
    $policy$, table_name);
    EXECUTE format($policy$
      CREATE POLICY duckguard_insert ON %I
      FOR INSERT WITH CHECK (
        table_id IN (
          SELECT dt.table_id
          FROM ducklake_table AS dt
          WHERE dt.schema_id IN (
            SELECT duckguard.get_schema_ids_for_user_with_permission(current_user, 'own')
          )
        )
      )
    $policy$, table_name);
    EXECUTE format($policy$
      CREATE POLICY duckguard_update ON %I
      FOR UPDATE USING (
        table_id IN (
          SELECT dt.table_id
          FROM ducklake_table AS dt
          WHERE dt.schema_id IN (
            SELECT duckguard.get_schema_ids_for_user_with_permission(current_user, 'own')
          )
        )
      )
    $policy$, table_name);
    EXECUTE format($policy$
      CREATE POLICY duckguard_delete ON %I
      FOR DELETE USING (
        table_id IN (
          SELECT dt.table_id
          FROM ducklake_table AS dt
          WHERE dt.schema_id IN (
            SELECT duckguard.get_schema_ids_for_user_with_permission(current_user, 'own')
          )
        )
      )
    $policy$, table_name);
  END LOOP;

  FOREACH table_name IN ARRAY ARRAY[
    'ducklake_column',
    'ducklake_column_tag',
    'ducklake_column_mapping'
  ] LOOP
    EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', table_name);
    EXECUTE format('DROP POLICY IF EXISTS duckguard_select ON %I', table_name);
    EXECUTE format('DROP POLICY IF EXISTS duckguard_insert ON %I', table_name);
    EXECUTE format('DROP POLICY IF EXISTS duckguard_update ON %I', table_name);
    EXECUTE format('DROP POLICY IF EXISTS duckguard_delete ON %I', table_name);
    EXECUTE format($policy$
      CREATE POLICY duckguard_select ON %I
      FOR SELECT USING (
        table_id IN (
          SELECT dt.table_id
          FROM ducklake_table AS dt
          WHERE dt.schema_id IN (
            SELECT duckguard.get_schema_ids_for_user_with_permission(current_user, 'usage')
          )
        )
        OR table_id IN (
          SELECT dt.table_id
          FROM ducklake_table AS dt
          WHERE dt.schema_id IN (
            SELECT duckguard.get_schema_ids_for_user_with_permission(current_user, 'own')
          )
        )
        OR
        table_id IN (SELECT duckguard.get_table_ids_for_user_with_permission(current_user, 'select'))
        OR table_id IN (SELECT duckguard.get_table_ids_for_user_with_permission(current_user, 'insert'))
        OR table_id IN (SELECT duckguard.get_table_ids_for_user_with_permission(current_user, 'update'))
        OR table_id IN (SELECT duckguard.get_table_ids_for_user_with_permission(current_user, 'delete'))
        OR table_id IN (SELECT duckguard.get_table_ids_for_user_with_permission(current_user, 'own'))
      )
    $policy$, table_name);
    EXECUTE format($policy$
      CREATE POLICY duckguard_insert ON %I
      FOR INSERT WITH CHECK (
        table_id IN (SELECT duckguard.get_table_ids_for_user_with_permission(current_user, 'own'))
        OR table_id IN (SELECT duckguard.get_table_ids_for_user_with_permission(current_user, 'create'))
      )
    $policy$, table_name);
    EXECUTE format($policy$
      CREATE POLICY duckguard_update ON %I
      FOR UPDATE USING (
        table_id IN (
          SELECT duckguard.get_table_ids_for_user_with_permission(current_user, 'own')
        )
      )
    $policy$, table_name);
    EXECUTE format($policy$
      CREATE POLICY duckguard_delete ON %I
      FOR DELETE USING (
        table_id IN (
          SELECT duckguard.get_table_ids_for_user_with_permission(current_user, 'own')
        )
      )
    $policy$, table_name);
  END LOOP;

  EXECUTE 'ALTER TABLE ducklake_tag ENABLE ROW LEVEL SECURITY';
  EXECUTE 'DROP POLICY IF EXISTS duckguard_select ON ducklake_tag';
  EXECUTE 'DROP POLICY IF EXISTS duckguard_insert ON ducklake_tag';
  EXECUTE 'DROP POLICY IF EXISTS duckguard_update ON ducklake_tag';
  EXECUTE 'DROP POLICY IF EXISTS duckguard_delete ON ducklake_tag';
  EXECUTE $policy$
    CREATE POLICY duckguard_select ON ducklake_tag
    FOR SELECT USING (true)
  $policy$;
  EXECUTE $policy$
    CREATE POLICY duckguard_insert ON ducklake_tag
    FOR INSERT WITH CHECK (
      object_id IN (
        SELECT dt.table_id
        FROM ducklake_table AS dt
        WHERE dt.schema_id IN (
          SELECT duckguard.get_schema_ids_for_user_with_permission(current_user, 'own')
        )
      )
    )
  $policy$;
  EXECUTE $policy$
    CREATE POLICY duckguard_update ON ducklake_tag
    FOR UPDATE USING (
      object_id IN (
        SELECT dt.table_id
        FROM ducklake_table AS dt
        WHERE dt.schema_id IN (
          SELECT duckguard.get_schema_ids_for_user_with_permission(current_user, 'own')
        )
      )
    )
  $policy$;
  EXECUTE $policy$
    CREATE POLICY duckguard_delete ON ducklake_tag
    FOR DELETE USING (
      object_id IN (
        SELECT dt.table_id
        FROM ducklake_table AS dt
        WHERE dt.schema_id IN (
          SELECT duckguard.get_schema_ids_for_user_with_permission(current_user, 'own')
        )
      )
    )
  $policy$;

  EXECUTE 'ALTER TABLE ducklake_inlined_data_tables ENABLE ROW LEVEL SECURITY';
  EXECUTE 'DROP POLICY IF EXISTS duckguard_select ON ducklake_inlined_data_tables';
  EXECUTE 'DROP POLICY IF EXISTS duckguard_insert ON ducklake_inlined_data_tables';
  EXECUTE 'DROP POLICY IF EXISTS duckguard_update ON ducklake_inlined_data_tables';
  EXECUTE 'DROP POLICY IF EXISTS duckguard_delete ON ducklake_inlined_data_tables';
  EXECUTE $policy$
    CREATE POLICY duckguard_select ON ducklake_inlined_data_tables
    FOR SELECT USING (
      table_id IN (SELECT duckguard.get_table_ids_for_user_with_permission(current_user, 'select'))
      OR table_id IN (SELECT duckguard.get_table_ids_for_user_with_permission(current_user, 'insert'))
      OR table_id IN (SELECT duckguard.get_table_ids_for_user_with_permission(current_user, 'update'))
      OR table_id IN (SELECT duckguard.get_table_ids_for_user_with_permission(current_user, 'delete'))
      OR table_id IN (SELECT duckguard.get_table_ids_for_user_with_permission(current_user, 'own'))
    )
  $policy$;
  EXECUTE $policy$
    CREATE POLICY duckguard_insert ON ducklake_inlined_data_tables
    FOR INSERT WITH CHECK (
      table_id IN (SELECT duckguard.get_table_ids_for_user_with_permission(current_user, 'insert'))
      OR table_id IN (SELECT duckguard.get_table_ids_for_user_with_permission(current_user, 'update'))
      OR table_id IN (SELECT duckguard.get_table_ids_for_user_with_permission(current_user, 'delete'))
      OR table_id IN (SELECT duckguard.get_table_ids_for_user_with_permission(current_user, 'own'))
      OR table_id IN (SELECT duckguard.get_table_ids_for_user_with_permission(current_user, 'create'))
    )
  $policy$;
  EXECUTE $policy$
    CREATE POLICY duckguard_update ON ducklake_inlined_data_tables
    FOR UPDATE USING (
      table_id IN (SELECT duckguard.get_table_ids_for_user_with_permission(current_user, 'update'))
      OR table_id IN (SELECT duckguard.get_table_ids_for_user_with_permission(current_user, 'delete'))
      OR table_id IN (SELECT duckguard.get_table_ids_for_user_with_permission(current_user, 'own'))
    )
  $policy$;
  EXECUTE $policy$
    CREATE POLICY duckguard_delete ON ducklake_inlined_data_tables
    FOR DELETE USING (
      table_id IN (SELECT duckguard.get_table_ids_for_user_with_permission(current_user, 'delete'))
      OR table_id IN (SELECT duckguard.get_table_ids_for_user_with_permission(current_user, 'own'))
    )
  $policy$;

  EXECUTE 'ALTER TABLE ducklake_snapshot_changes ENABLE ROW LEVEL SECURITY';
  EXECUTE 'DROP POLICY IF EXISTS duckguard_select ON ducklake_snapshot_changes';
  EXECUTE 'DROP POLICY IF EXISTS duckguard_insert ON ducklake_snapshot_changes';
  EXECUTE 'DROP POLICY IF EXISTS duckguard_update ON ducklake_snapshot_changes';
  EXECUTE 'DROP POLICY IF EXISTS duckguard_delete ON ducklake_snapshot_changes';
  EXECUTE $policy$
    CREATE POLICY duckguard_select ON ducklake_snapshot_changes
    FOR SELECT USING (true)
  $policy$;
  EXECUTE $policy$
    CREATE POLICY duckguard_insert ON ducklake_snapshot_changes
    FOR INSERT WITH CHECK (
      changes_made IS NULL
      OR changes_made !~ '(^|,)inlined_(insert|delete):'
      OR EXISTS (
        SELECT 1
        FROM duckguard.get_table_ids_for_user_with_permission(current_user, 'insert') AS allowed_table_id
        WHERE changes_made ~ ('(^|,)inlined_insert:' || allowed_table_id::text || '(,|$)')
          AND changes_made !~ ('(^|,)inlined_delete:' || allowed_table_id::text || '(,|$)')
      )
      OR EXISTS (
        SELECT 1
        FROM duckguard.get_table_ids_for_user_with_permission(current_user, 'update') AS allowed_table_id
        WHERE changes_made ~ ('(^|,)inlined_insert:' || allowed_table_id::text || '(,|$)')
          AND changes_made ~ ('(^|,)inlined_delete:' || allowed_table_id::text || '(,|$)')
      )
      OR EXISTS (
        SELECT 1
        FROM duckguard.get_table_ids_for_user_with_permission(current_user, 'delete') AS allowed_table_id
        WHERE changes_made !~ ('(^|,)inlined_insert:' || allowed_table_id::text || '(,|$)')
          AND changes_made ~ ('(^|,)inlined_delete:' || allowed_table_id::text || '(,|$)')
      )
    )
  $policy$;
  EXECUTE $policy$
    CREATE POLICY duckguard_update ON ducklake_snapshot_changes
    FOR UPDATE USING (true)
  $policy$;
  EXECUTE $policy$
    CREATE POLICY duckguard_delete ON ducklake_snapshot_changes
    FOR DELETE USING (true)
  $policy$;

  FOR inlined_record IN
    SELECT idt.table_id, idt.table_name
    FROM ducklake_inlined_data_tables AS idt
  LOOP
    EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', inlined_record.table_name);
    EXECUTE format('DROP POLICY IF EXISTS duckguard_select ON %I', inlined_record.table_name);
    EXECUTE format('DROP POLICY IF EXISTS duckguard_insert ON %I', inlined_record.table_name);
    EXECUTE format('DROP POLICY IF EXISTS duckguard_update ON %I', inlined_record.table_name);
    EXECUTE format('DROP POLICY IF EXISTS duckguard_delete ON %I', inlined_record.table_name);
    EXECUTE format($policy$
      CREATE POLICY duckguard_select ON %I
      FOR SELECT USING (
        %s IN (SELECT duckguard.get_table_ids_for_user_with_permission(current_user, 'select'))
      )
    $policy$, inlined_record.table_name, inlined_record.table_id);
    EXECUTE format($policy$
      CREATE POLICY duckguard_insert ON %I
      FOR INSERT WITH CHECK (
        %s IN (SELECT duckguard.get_table_ids_for_user_with_permission(current_user, 'insert'))
        OR %s IN (SELECT duckguard.get_table_ids_for_user_with_permission(current_user, 'update'))
      )
    $policy$, inlined_record.table_name, inlined_record.table_id, inlined_record.table_id);
    EXECUTE format($policy$
      CREATE POLICY duckguard_update ON %I
      FOR UPDATE USING (
        %s IN (SELECT duckguard.get_table_ids_for_user_with_permission(current_user, 'update'))
        OR %s IN (SELECT duckguard.get_table_ids_for_user_with_permission(current_user, 'delete'))
      )
    $policy$, inlined_record.table_name, inlined_record.table_id, inlined_record.table_id);
    EXECUTE format($policy$
      CREATE POLICY duckguard_delete ON %I
      FOR DELETE USING (
        %s IN (SELECT duckguard.get_table_ids_for_user_with_permission(current_user, 'delete'))
      )
    $policy$, inlined_record.table_name, inlined_record.table_id);
  END LOOP;
END;
$$;
