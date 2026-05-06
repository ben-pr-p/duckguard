import { DuckDBConnection } from "@duckdb/node-api";
import { spawn } from "node:child_process";
import { mkdir, mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";

const OUTPUT_PATH = resolve("docs/ducklake_schema.sql");

const PGHOST = process.env.PGHOST ?? "127.0.0.1";
const PGPORT = process.env.PGPORT ?? "5432";
const PGDATABASE = process.env.PGDATABASE ?? "postgres";
const PGUSER = process.env.PGUSER ?? "postgres";
const PGPASSWORD = process.env.PGPASSWORD;
const PGSSLMODE = process.env.PGSSLMODE ?? "disable";
const DUCKLAKE_METADATA_SCHEMA =
  process.env.DUCKLAKE_METADATA_SCHEMA ?? "ducklake_schema_export";

type CommandResult = {
  stdout: string;
  stderr: string;
};

function runCommand(
  command: string,
  args: string[],
  env: NodeJS.ProcessEnv = {},
): Promise<CommandResult> {
  return new Promise((resolveCommand, rejectCommand) => {
    const child = spawn(command, args, {
      env: { ...process.env, ...env },
      stdio: ["ignore", "pipe", "pipe"],
    });

    let stdout = "";
    let stderr = "";

    child.stdout.setEncoding("utf8");
    child.stderr.setEncoding("utf8");
    child.stdout.on("data", (chunk) => {
      stdout += chunk;
    });
    child.stderr.on("data", (chunk) => {
      stderr += chunk;
    });
    child.on("error", rejectCommand);
    child.on("close", (code) => {
      if (code === 0) {
        resolveCommand({ stdout, stderr });
        return;
      }

      rejectCommand(
        new Error(
          `${command} ${args.join(" ")} failed with exit code ${code}\n${stderr}`,
        ),
      );
    });
  });
}

function quoteSqlString(value: string): string {
  return value.replaceAll("'", "''");
}

function quoteSqlIdentifier(value: string): string {
  return `"${value.replaceAll('"', '""')}"`;
}

function quoteConnValue(value: string): string {
  return `'${value.replaceAll("\\", "\\\\").replaceAll("'", "\\'")}'`;
}

function postgresConnectionString(): string {
  const parts = [
    `dbname=${quoteConnValue(PGDATABASE)}`,
    `host=${quoteConnValue(PGHOST)}`,
    `port=${quoteConnValue(PGPORT)}`,
    `user=${quoteConnValue(PGUSER)}`,
    `sslmode=${quoteConnValue(PGSSLMODE)}`,
  ];

  if (PGPASSWORD) {
    parts.push(`password=${quoteConnValue(PGPASSWORD)}`);
  }

  return parts.join(" ");
}

async function initializeDuckLakeCatalog(dataPath: string) {
  const connection = await DuckDBConnection.create();
  const catalog = postgresConnectionString();

  try {
    await connection.run("INSTALL ducklake");
    await connection.run("LOAD ducklake");
    await connection.run("INSTALL postgres");
    await connection.run("LOAD postgres");
    await connection.run(`
      ATTACH '${quoteSqlString(catalog)}'
        AS ducklake_metadata_catalog
        (TYPE postgres, SCHEMA '${quoteSqlString(DUCKLAKE_METADATA_SCHEMA)}')
    `);
    await connection.run(
      `CREATE SCHEMA IF NOT EXISTS ducklake_metadata_catalog.${quoteSqlIdentifier(DUCKLAKE_METADATA_SCHEMA)}`,
    );
    await connection.run("DETACH ducklake_metadata_catalog");
    await connection.run(`
      ATTACH 'ducklake:postgres:${quoteSqlString(catalog)}'
        AS ducklake_schema_export
        (
          DATA_PATH '${quoteSqlString(dataPath)}',
          METADATA_SCHEMA '${quoteSqlString(DUCKLAKE_METADATA_SCHEMA)}'
        )
    `);
    await connection.run("USE ducklake_schema_export");

    // Force DuckLake to create table-level catalog metadata, not just attach metadata.
    await connection.run(
      "CREATE TABLE IF NOT EXISTS schema_export_probe (id INTEGER, value VARCHAR)",
    );
    await connection.run("DROP TABLE schema_export_probe");
  } finally {
    connection.closeSync();
  }
}

async function exportMetadataSchema() {
  const { stdout } = await runCommand(
    "pg_dump",
    [
      "--schema-only",
      "--no-owner",
      "--no-privileges",
      "--host",
      PGHOST,
      "--port",
      PGPORT,
      "--username",
      PGUSER,
      "--dbname",
      PGDATABASE,
      "--schema",
      DUCKLAKE_METADATA_SCHEMA,
    ],
    {
      PGSSLMODE,
      ...(PGPASSWORD ? { PGPASSWORD } : {}),
    },
  );

  await mkdir(dirname(OUTPUT_PATH), { recursive: true });
  await writeFile(OUTPUT_PATH, stdout);
}

async function main() {
  const tempRoot = await mkdtemp(join(tmpdir(), "duckguard-ducklake-schema-"));
  const dataPath = join(tempRoot, "data");

  try {
    await mkdir(dataPath, { recursive: true });
    await initializeDuckLakeCatalog(dataPath);
    await exportMetadataSchema();
    console.log(`Wrote ${OUTPUT_PATH}`);
  } finally {
    await rm(tempRoot, { recursive: true, force: true });
  }
}

await main();
