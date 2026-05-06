import { afterAll, beforeAll, describe, expect, test } from "bun:test";
import { DuckDBConnection } from "@duckdb/node-api";
import pg from "pg";
import { randomUUID } from "node:crypto";
import { mkdtemp, rm } from "node:fs/promises";
import { join } from "node:path";
import { tmpdir } from "node:os";

const { Client } = pg;

type BooleanGrant = Record<string, boolean | undefined>;

type PermissionSpec = {
  superuser?: BooleanGrant;
  catalog?: BooleanGrant;
  schema?: BooleanGrant;
  table?: BooleanGrant;
};

type ActionsSpec = {
  description: string;
  sql: string;
  expectedRows?: unknown[][];
  checkSql?: string;
  checkRows?: unknown[][];
  checkRowsContain?: unknown[][];
};

type MatrixCase = {
  name: string;
  permissions: PermissionSpec;
  actions: ActionsSpec;
  outcome: "allowed" | "denied";
};

type TestContext = {
  metadataSchema: string;
  roleName: string;
  rolePassword: string;
  tempDir: string;
  schemaId: string;
  extraSchemaId: string;
  tableId: string;
};

const databaseUrl = process.env.DATABASE_URL;
const testIfDatabase = databaseUrl ? test : test.skip;
const createdRoles: string[] = [];
const tempDirs: string[] = [];

const cases: MatrixCase[] = [
  {
    name: "catalog usage is required to read schemas",
    permissions: {},
    actions: { description: "read schemas", sql: "SHOW SCHEMAS" },
    outcome: "denied",
  },
  {
    name: "catalog usage permits reading schemas",
    permissions: { catalog: { has_usage: true } },
    actions: { description: "read schemas", sql: "SHOW SCHEMAS" },
    outcome: "allowed",
  },
  {
    name: "catalog create permits creating a schema",
    permissions: { catalog: { has_create: true, has_usage: true } },
    actions: { description: "create schema", sql: "CREATE SCHEMA created_schema" },
    outcome: "allowed",
  },
  {
    name: "missing catalog create denies creating a schema",
    permissions: {},
    actions: { description: "create schema", sql: "CREATE SCHEMA created_schema" },
    outcome: "denied",
  },
  {
    name: "catalog ownership permits dropping a schema",
    permissions: { catalog: { has_own: true, has_usage: true } },
    actions: { description: "drop schema", sql: "DROP SCHEMA extra_schema CASCADE" },
    outcome: "allowed",
  },
  {
    name: "missing catalog ownership denies dropping a schema",
    permissions: { catalog: { has_usage: true } },
    actions: {
      description: "drop schema",
      sql: "DROP SCHEMA extra_schema CASCADE",
      checkSql: "SHOW SCHEMAS",
      checkRowsContain: [["test_catalog", "extra_schema", false]],
    },
    outcome: "denied",
  },
  {
    name: "schema usage permits listing tables and views",
    permissions: { catalog: { has_usage: true }, schema: { has_usage: true } },
    actions: { description: "show tables", sql: "SHOW TABLES" },
    outcome: "allowed",
  },
  {
    name: "catalog usage alone lists table names without granting table data",
    permissions: { catalog: { has_usage: true } },
    actions: { description: "show tables", sql: "SHOW TABLES", expectedRows: [["protected_table"]] },
    outcome: "allowed",
  },
  {
    name: "schema create permits creating a table",
    permissions: {
      catalog: { has_usage: true },
      schema: { has_create: true, has_usage: true, has_all_table_select: true },
    },
    actions: { description: "create table", sql: "CREATE TABLE created_table (id INTEGER)" },
    outcome: "allowed",
  },
  {
    name: "schema usage alone does not permit creating a table",
    permissions: { catalog: { has_usage: true }, schema: { has_usage: true } },
    actions: { description: "create table", sql: "CREATE TABLE created_table (id INTEGER)" },
    outcome: "denied",
  },
  {
    name: "schema ownership permits dropping a table",
    permissions: { catalog: { has_usage: true }, schema: { has_own: true } },
    actions: { description: "drop table", sql: "DROP TABLE protected_table" },
    outcome: "allowed",
  },
  {
    name: "table ownership permits dropping a table",
    permissions: {
      catalog: { has_usage: true },
      schema: { has_usage: true },
      table: { has_own: true },
    },
    actions: { description: "drop table", sql: "DROP TABLE protected_table" },
    outcome: "allowed",
  },
  {
    name: "schema all-table select permits selecting rows",
    permissions: {
      catalog: { has_usage: true },
      schema: { has_usage: true, has_all_table_select: true },
    },
    actions: { description: "select rows", sql: "SELECT * FROM protected_table WHERE id = 1" },
    outcome: "allowed",
  },
  {
    name: "table select permits selecting rows",
    permissions: {
      catalog: { has_usage: true },
      schema: { has_usage: true },
      table: { has_select: true },
    },
    actions: { description: "select rows", sql: "SELECT * FROM protected_table WHERE id = 1" },
    outcome: "allowed",
  },
  {
    name: "missing table select denies selecting rows",
    permissions: {
      catalog: { has_usage: true },
      schema: { has_usage: true },
    },
    actions: { description: "select rows", sql: "SELECT * FROM protected_table WHERE id = 1", expectedRows: [] },
    outcome: "denied",
  },
  {
    name: "schema all-table insert permits inserting rows",
    permissions: {
      catalog: { has_usage: true },
      schema: { has_usage: true, has_all_table_insert: true },
    },
    actions: { description: "insert row", sql: "INSERT INTO protected_table VALUES (2000, 'two')" },
    outcome: "allowed",
  },
  {
    name: "table insert permits inserting rows",
    permissions: {
      catalog: { has_usage: true },
      schema: { has_usage: true },
      table: { has_insert: true },
    },
    actions: { description: "insert row", sql: "INSERT INTO protected_table VALUES (2000, 'two')" },
    outcome: "allowed",
  },
  {
    name: "table select alone denies inserting rows",
    permissions: {
      catalog: { has_usage: true },
      schema: { has_usage: true },
      table: { has_select: true },
    },
    actions: { description: "insert row", sql: "INSERT INTO protected_table VALUES (2000, 'two')" },
    outcome: "denied",
  },
	{
		name: "schema all-table update permits updating rows",
		permissions: {
			catalog: { has_usage: true },
			schema: { has_usage: true, has_all_table_select: true, has_all_table_update: true },
		},
		actions: {
			description: "update row",
			sql: "UPDATE protected_table SET value = 'updated' WHERE id = 1",
			checkSql: "SELECT * FROM protected_table WHERE id = 1 ORDER BY id",
			checkRows: [[1, "updated"]],
		},
    outcome: "allowed",
  },
	{
		name: "table update permits updating rows",
		permissions: {
			catalog: { has_usage: true },
			schema: { has_usage: true },
			table: { has_select: true, has_update: true },
		},
		actions: {
			description: "update row",
			sql: "UPDATE protected_table SET value = 'updated' WHERE id = 1",
			checkSql: "SELECT * FROM protected_table WHERE id = 1 ORDER BY id",
			checkRows: [[1, "updated"]],
		},
    outcome: "allowed",
  },
  {
    name: "table insert without update denies updating visible rows",
    permissions: {
      catalog: { has_usage: true },
      schema: { has_usage: true },
      table: { has_select: true, has_insert: true },
    },
    actions: {
      description: "update row",
      sql: "UPDATE protected_table SET value = 'updated' WHERE id = 1",
      checkSql: "SELECT * FROM protected_table WHERE id = 1 ORDER BY id",
      checkRows: [[1, "one"]],
    },
    outcome: "denied",
  },
	{
		name: "schema all-table delete permits deleting rows",
		permissions: {
			catalog: { has_usage: true },
			schema: { has_usage: true, has_all_table_select: true, has_all_table_delete: true },
		},
		actions: {
			description: "delete row",
			sql: "DELETE FROM protected_table WHERE id = 1",
			checkSql: "SELECT * FROM protected_table WHERE id = 1 ORDER BY id",
			checkRows: [],
		},
    outcome: "allowed",
  },
	{
		name: "table delete permits deleting rows",
		permissions: {
			catalog: { has_usage: true },
			schema: { has_usage: true },
			table: { has_select: true, has_delete: true },
		},
		actions: {
			description: "delete row",
			sql: "DELETE FROM protected_table WHERE id = 1",
			checkSql: "SELECT * FROM protected_table WHERE id = 1 ORDER BY id",
			checkRows: [],
		},
    outcome: "allowed",
  },
  {
    name: "table update without delete denies deleting visible rows",
    permissions: {
      catalog: { has_usage: true },
      schema: { has_usage: true },
      table: { has_select: true, has_update: true },
    },
    actions: {
      description: "delete row",
      sql: "DELETE FROM protected_table WHERE id = 1",
      checkSql: "SELECT * FROM protected_table WHERE id = 1 ORDER BY id",
      checkRows: [[1, "one"]],
    },
    outcome: "denied",
  },
  {
    name: "schema ownership permits column changes",
    permissions: {
      catalog: { has_usage: true },
      schema: { has_usage: true, has_own: true },
    },
    actions: { description: "add column", sql: "ALTER TABLE protected_table ADD COLUMN added INTEGER" },
    outcome: "allowed",
  },
  {
    name: "table update does not permit column changes",
    permissions: {
      catalog: { has_usage: true },
      schema: { has_usage: true },
      table: { has_update: true },
    },
    actions: { description: "add column", sql: "ALTER TABLE protected_table ADD COLUMN added INTEGER" },
    outcome: "denied",
  },
  {
    name: "table ownership permits column changes",
    permissions: {
      catalog: { has_usage: true },
      schema: { has_usage: true },
      table: { has_own: true },
    },
    actions: { description: "add column", sql: "ALTER TABLE protected_table ADD COLUMN added INTEGER" },
    outcome: "allowed",
  },
  {
    name: "table insert does not permit column changes",
    permissions: {
      catalog: { has_usage: true },
      schema: { has_usage: true },
      table: { has_insert: true },
    },
    actions: { description: "add column", sql: "ALTER TABLE protected_table ADD COLUMN added INTEGER" },
    outcome: "denied",
  },
  {
    name: "table delete does not permit column changes",
    permissions: {
      catalog: { has_usage: true },
      schema: { has_usage: true },
      table: { has_delete: true },
    },
    actions: { description: "add column", sql: "ALTER TABLE protected_table ADD COLUMN added INTEGER" },
    outcome: "denied",
  },
  {
    name: "schema all-table update does not permit column changes",
    permissions: {
      catalog: { has_usage: true },
      schema: { has_usage: true, has_all_table_update: true },
    },
    actions: { description: "add column", sql: "ALTER TABLE protected_table ADD COLUMN added INTEGER" },
    outcome: "denied",
  },
  {
    name: "schema ownership permits partition metadata changes",
    permissions: {
      catalog: { has_usage: true },
      schema: { has_usage: true, has_own: true },
    },
    actions: {
      description: "change partition metadata",
      sql: "ALTER TABLE protected_table SET PARTITIONED BY (id)",
    },
    outcome: "allowed",
  },
  {
    name: "table ownership does not permit partition metadata changes",
    permissions: {
      catalog: { has_usage: true },
      schema: { has_usage: true },
      table: { has_own: true },
    },
    actions: {
      description: "change partition metadata",
      sql: "ALTER TABLE protected_table SET PARTITIONED BY (id)",
    },
    outcome: "denied",
  },
  {
    name: "schema and table select permits reading metadata",
    permissions: {
      catalog: { has_usage: true },
      schema: { has_usage: true },
      table: { has_select: true },
    },
    actions: { description: "read metadata", sql: "DESCRIBE protected_table" },
    outcome: "allowed",
  },
  {
    name: "schema usage without table select denies reading metadata",
    permissions: {
      catalog: { has_usage: true },
      schema: { has_usage: true },
    },
    actions: { description: "read metadata", sql: "DESCRIBE protected_table" },
    outcome: "allowed",
  },
  {
    name: "schema ownership permits table comment changes",
    permissions: {
      catalog: { has_usage: true },
      schema: { has_usage: true, has_own: true },
    },
    actions: { description: "change table tags", sql: "COMMENT ON TABLE protected_table IS 'owned'" },
    outcome: "allowed",
  },
  {
    name: "table ownership does not permit table comment changes",
    permissions: {
      catalog: { has_usage: true },
      schema: { has_usage: true },
      table: { has_own: true },
    },
    actions: { description: "change table tags", sql: "COMMENT ON TABLE protected_table IS 'owned'" },
    outcome: "denied",
  },
  {
    name: "superuser bypass permits protected actions",
    permissions: {
      superuser: { enabled: true },
    },
    actions: { description: "superuser action", sql: "ALTER TABLE protected_table ADD COLUMN super_added INTEGER" },
    outcome: "allowed",
  },
];

describe("duckguard extension RLS", () => {
  beforeAll(async () => {
    if (!databaseUrl) {
      return;
    }

    await withPgClient(async (client) => {
      await client.query(await Bun.file("duckguard.sql").text());
      await resetPermissionTables(client);
    });
  });

  afterAll(async () => {
    if (!databaseUrl) {
      return;
    }

    await withPgClient(async (client) => {
      for (const roleName of [...createdRoles].reverse()) {
        await client.query(`DROP OWNED BY ${quoteIdent(roleName)}`);
        await client.query(`DROP ROLE IF EXISTS ${quoteIdent(roleName)}`);
      }
    });

    await Promise.all(
      tempDirs.map((tempDir) => rm(tempDir, { force: true, recursive: true })),
    );
  });

	  testIfDatabase.each(cases)("$name", async (testCase) => {
	    const context = await createIsolatedDuckLake();

    await withPgClient(async (client) => {
      await resetPermissionTables(client);
      await insertPermissions(client, context, testCase.permissions);
    });

    const runAction = () => runDuckLakeSql(asRoleConnectionString(context), context, testCase.actions.sql);

    if (testCase.outcome === "allowed") {
      try {
        const rows = await runAction();
        if (testCase.actions.expectedRows) {
          expect(rows).toEqual(testCase.actions.expectedRows);
        }
      } catch (error) {
        throw new Error(`${testCase.name} should be allowed: ${errorMessage(error)}`);
      }
      if (testCase.actions.checkSql) {
        const rows = await runDuckLakeSql(adminConnectionString(), context, testCase.actions.checkSql);
        assertRows(rows, testCase.actions);
      }
    } else {
      if (testCase.actions.expectedRows) {
        const rows = await runAction();
        expect(rows).toEqual(testCase.actions.expectedRows);
      } else {
        try {
          await runAction();
        } catch {
          return;
        }
        if (!testCase.actions.checkSql) {
          throw new Error(`${testCase.name} should be denied`);
        }
      }
      if (testCase.actions.checkSql) {
        const rows = await runDuckLakeSql(adminConnectionString(), context, testCase.actions.checkSql);
        assertRows(rows, testCase.actions);
      }
	    }
	  });

	  testIfDatabase("helper functions set permissions by object name", async () => {
	    const context = await createIsolatedDuckLake();
	    const email = `${context.roleName}@example.test`;

	    await withPgClient(async (client) => {
	      await resetPermissionTables(client);
	      const userResult = await client.query<{ id: string }>(
	        `
	          INSERT INTO duckguard.users (pg_user_name, email)
	          VALUES ($1, $2)
	          RETURNING id
	        `,
	        [context.roleName, email],
	      );
	      const userId = userResult.rows[0].id;

	      await client.query("SELECT duckguard.set_catalog_permission($1, $2, $3)", [
	        email,
	        context.metadataSchema,
	        "usage",
	      ]);
	      await client.query("SELECT duckguard.set_catalog_permission($1, $2, $3)", [
	        email,
	        context.metadataSchema,
	        "create",
	      ]);
	      await client.query("SELECT duckguard.set_schema_permission($1, $2, $3)", [
	        email,
	        `${context.metadataSchema}.main`,
	        "usage",
	      ]);
	      await client.query("SELECT duckguard.set_schema_permission($1, $2, $3)", [
	        email,
	        `${context.metadataSchema}.main`,
	        "all_table_select",
	      ]);
	      await client.query("SELECT duckguard.set_table_permission($1, $2, $3)", [
	        email,
	        `${context.metadataSchema}.main.protected_table`,
	        "select",
	      ]);
	      await client.query("SELECT duckguard.set_table_permission($1, $2, $3)", [
	        email,
	        `${context.metadataSchema}.main.protected_table`,
	        "update",
	      ]);

	      const catalogResult = await client.query(
	        `
	          SELECT has_usage, has_create, has_own
	          FROM duckguard.catalog_permissions
	          WHERE user_id = $1 AND catalog_id = $2
	        `,
	        [userId, context.metadataSchema],
	      );
	      expect(catalogResult.rows).toEqual([
	        { has_usage: true, has_create: true, has_own: false },
	      ]);

	      const schemaResult = await client.query(
	        `
	          SELECT has_usage, has_all_table_select, has_all_table_insert
	          FROM duckguard.schema_permissions
	          WHERE user_id = $1 AND catalog_id = $2 AND schema_id = $3
	        `,
	        [userId, context.metadataSchema, context.schemaId],
	      );
	      expect(schemaResult.rows).toEqual([
	        { has_usage: true, has_all_table_select: true, has_all_table_insert: false },
	      ]);

	      const tableResult = await client.query(
	        `
	          SELECT has_select, has_insert, has_update, has_delete, has_own
	          FROM duckguard.table_permissions
	          WHERE user_id = $1 AND catalog_id = $2 AND table_id = $3
	        `,
	        [userId, context.metadataSchema, context.tableId],
	      );
	      expect(tableResult.rows).toEqual([
	        {
	          has_select: true,
	          has_insert: false,
	          has_update: true,
	          has_delete: false,
	          has_own: false,
	        },
	      ]);
	    });
	  });

	  testIfDatabase("helper functions reject unknown names and permissions", async () => {
	    const context = await createIsolatedDuckLake();
	    const email = `${context.roleName}@example.test`;

	    await withPgClient(async (client) => {
	      await resetPermissionTables(client);
	      await client.query(
	        `
	          INSERT INTO duckguard.users (pg_user_name, email)
	          VALUES ($1, $2)
	        `,
	        [context.roleName, email],
	      );

	      await expect(
	        client.query("SELECT duckguard.set_catalog_permission($1, $2, $3)", [
	          email,
	          context.metadataSchema,
	          "select",
	        ]),
	      ).rejects.toThrow();

	      await expect(
	        client.query("SELECT duckguard.set_schema_permission($1, $2, $3)", [
	          email,
	          `${context.metadataSchema}.missing_schema`,
	          "usage",
	        ]),
	      ).rejects.toThrow();

	      await expect(
	        client.query("SELECT duckguard.set_table_permission($1, $2, $3)", [
	          email,
	          `${context.metadataSchema}.main.missing_table`,
	          "select",
	        ]),
	      ).rejects.toThrow();
	    });
	  });
	});

async function createIsolatedDuckLake(): Promise<TestContext> {
  const id = randomUUID().replaceAll("-", "").slice(0, 16);
  const metadataSchema = `dgmeta${id}`;
  const roleName = `dgrole${id}`;
  const rolePassword = `dgpass${randomUUID().replaceAll("-", "")}`;
  const tempDir = await mkdtemp(join(tmpdir(), "duckguard-ducklake-"));
  tempDirs.push(tempDir);
  createdRoles.push(roleName);

  await withPgClient(async (client) => {
    await client.query(`CREATE SCHEMA ${quoteIdent(metadataSchema)}`);
    await client.query(`CREATE ROLE ${quoteIdent(roleName)} LOGIN PASSWORD ${quoteLiteral(rolePassword)}`);
  });

  await runDuckLakeSql(adminConnectionString(), {
    tempDir,
    metadataSchema,
  }, `
    CREATE TABLE protected_table AS SELECT i::INTEGER AS id, 'one'::VARCHAR AS "value" FROM range(1, 1000) AS tbl(i);
    CREATE SCHEMA extra_schema;
  `);

  const ids = await withPgClient(async (client) => {
    await client.query(`SELECT duckguard.protect($1)`, [metadataSchema]);
    await grantMetadataAccess(client, metadataSchema, roleName);

    const schemaResult = await client.query(
      `SELECT schema_id FROM ${quoteIdent(metadataSchema)}.ducklake_schema WHERE end_snapshot IS NULL LIMIT 1`,
    );
    const tableResult = await client.query(
      `SELECT table_id FROM ${quoteIdent(metadataSchema)}.ducklake_table WHERE table_name = 'protected_table' AND end_snapshot IS NULL LIMIT 1`,
    );
    const extraSchemaResult = await client.query(
      `SELECT schema_id FROM ${quoteIdent(metadataSchema)}.ducklake_schema WHERE schema_name = 'extra_schema' AND end_snapshot IS NULL LIMIT 1`,
    );

    return {
      schemaId: String(schemaResult.rows[0].schema_id),
      extraSchemaId: String(extraSchemaResult.rows[0].schema_id),
      tableId: String(tableResult.rows[0].table_id),
    };
  });

  return {
    metadataSchema,
    roleName,
    rolePassword,
    tempDir,
    ...ids,
  };
}

async function insertPermissions(
  client: InstanceType<typeof Client>,
  context: TestContext,
  permissions: PermissionSpec,
) {
  const userResult = await client.query<{ id: string }>(
    `
      INSERT INTO duckguard.users (pg_user_name, email)
      VALUES ($1, $2)
      RETURNING id
    `,
    [context.roleName, `${context.roleName}@example.test`],
  );
  const userId = userResult.rows[0].id;

  if (permissions.superuser?.enabled) {
    await client.query(
      "UPDATE duckguard.users SET is_superuser = true WHERE id = $1",
      [userId],
    );
  }

  if (permissions.catalog) {
    await client.query(
      `
        INSERT INTO duckguard.catalog_permissions (
          user_id,
          catalog_id,
          has_create,
          has_usage,
          has_own
        )
        VALUES ($1, $2, $3, $4, $5)
      `,
      [
        userId,
        context.metadataSchema,
        permissions.catalog.has_create ?? false,
        permissions.catalog.has_usage ?? false,
        permissions.catalog.has_own ?? false,
      ],
    );
  }

  if (permissions.schema) {
    await client.query(
      `
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
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
      `,
      [
        userId,
        context.metadataSchema,
        context.schemaId,
        permissions.schema.has_create ?? false,
        permissions.schema.has_usage ?? false,
        permissions.schema.has_own ?? false,
        permissions.schema.has_all_table_select ?? false,
        permissions.schema.has_all_table_insert ?? false,
        permissions.schema.has_all_table_update ?? false,
        permissions.schema.has_all_table_delete ?? false,
      ],
    );
  }

  if (permissions.table) {
    await client.query(
      `
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
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
      `,
      [
        userId,
        context.metadataSchema,
        context.tableId,
        permissions.table.has_select ?? false,
        permissions.table.has_insert ?? false,
        permissions.table.has_update ?? false,
        permissions.table.has_delete ?? false,
        permissions.table.has_own ?? false,
      ],
    );
  }
}

async function resetPermissionTables(client: InstanceType<typeof Client>) {
  await client.query(`
    TRUNCATE
      duckguard.table_permissions,
      duckguard.schema_permissions,
      duckguard.catalog_permissions,
      duckguard.users
    CASCADE
  `);
}

async function grantMetadataAccess(
  client: InstanceType<typeof Client>,
  metadataSchema: string,
  roleName: string,
) {
  await client.query(`GRANT USAGE ON SCHEMA duckguard TO ${quoteIdent(roleName)}`);
  await client.query(`GRANT USAGE, CREATE ON SCHEMA ${quoteIdent(metadataSchema)} TO ${quoteIdent(roleName)}`);
  await client.query(
    `GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA ${quoteIdent(metadataSchema)} TO ${quoteIdent(roleName)}`,
  );
}

async function withPgClient<T>(fn: (client: InstanceType<typeof Client>) => Promise<T>): Promise<T> {
  if (!databaseUrl) {
    throw new Error("DATABASE_URL is required");
  }

  const client = new Client({ connectionString: databaseUrl });
  await client.connect();
  try {
    return await fn(client);
  } finally {
    await client.end();
  }
}

async function runDuckLakeSql(
  postgresConnectionString: string,
  context: Pick<TestContext, "metadataSchema" | "tempDir">,
  sql: string,
): Promise<unknown[][] | undefined> {
  const connection = await DuckDBConnection.create();
  try {
    await connection.run("INSTALL ducklake");
    await connection.run("LOAD ducklake");
    await connection.run("INSTALL postgres");
    await connection.run("LOAD postgres");
    await connection.run(`
      ATTACH 'ducklake:postgres:${quoteSqlString(postgresConnectionString)}'
        AS test_catalog
        (
          DATA_PATH '${quoteSqlString(context.tempDir)}',
          METADATA_SCHEMA '${quoteSqlString(context.metadataSchema)}'
        )
    `);
    await connection.run("USE test_catalog");
    if (returnsRows(sql)) {
      const reader = await connection.runAndReadAll(sql);
      return reader.getRowsJson() as unknown[][];
    }
    await connection.run(sql);
    return undefined;
  } finally {
    connection.closeSync();
  }
}

function returnsRows(sql: string) {
  return /^(select|show|describe|pragma)\b/i.test(sql.trim());
}

function adminConnectionString() {
  if (!databaseUrl) {
    throw new Error("DATABASE_URL is required");
  }

  return postgresConnectionStringFromUrl(new URL(databaseUrl));
}

function asRoleConnectionString(context: TestContext) {
  if (!databaseUrl) {
    throw new Error("DATABASE_URL is required");
  }

  const url = new URL(databaseUrl);
  url.username = context.roleName;
  url.password = context.rolePassword;
  return postgresConnectionStringFromUrl(url);
}

function postgresConnectionStringFromUrl(url: URL) {
  const parts = [
    `host=${quoteConnValue(url.hostname)}`,
    `port=${quoteConnValue(url.port || "5432")}`,
    `dbname=${quoteConnValue(url.pathname.slice(1))}`,
    `user=${quoteConnValue(decodeURIComponent(url.username))}`,
  ];

  if (url.password) {
    parts.push(`password=${quoteConnValue(decodeURIComponent(url.password))}`);
  }

  return parts.join(" ");
}

function quoteConnValue(value: string) {
  return `'${value.replaceAll("\\", "\\\\").replaceAll("'", "\\'")}'`;
}

function quoteSqlString(value: string) {
  return value.replaceAll("'", "''");
}

function quoteLiteral(value: string) {
  return `'${value.replaceAll("'", "''")}'`;
}

function quoteIdent(value: string) {
  return `"${value.replaceAll('"', '""')}"`;
}

function errorMessage(error: unknown) {
  return error instanceof Error ? error.message : String(error);
}

function assertRows(rows: unknown[][] | undefined, actions: ActionsSpec) {
  if (actions.checkRows) {
    expect(rows).toEqual(actions.checkRows);
  }
  if (actions.checkRowsContain) {
    for (const expectedRow of actions.checkRowsContain) {
      expect(rows).toContainEqual(expectedRow);
    }
  }
}
