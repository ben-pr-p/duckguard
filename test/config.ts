import { cleanEnv, str, url } from "envalid";

export const env = cleanEnv(process.env, {
  NODE_ENV: str({
    choices: ["development", "test", "production"],
    default: "development",
    desc: "Runtime environment.",
  }),
  DATABASE_URL: url({
    desc: "PostgreSQL database URL used by the app and graphile-migrate.",
    example: "postgres://duckguard:duckguard@localhost:5432/duckguard",
  }),
  SHADOW_DATABASE_URL: url({
    default: undefined,
    desc: "Optional PostgreSQL shadow database URL for graphile-migrate development workflows.",
    example: "postgres://duckguard:duckguard@localhost:5432/duckguard_shadow",
  }),
  ROOT_DATABASE_URL: url({
    default: undefined,
    desc: "Optional root PostgreSQL URL used by graphile-migrate reset/commit operations.",
    example: "postgres://postgres:postgres@localhost:5432/postgres",
  }),
});

export const config = {
  nodeEnv: env.NODE_ENV,
  isDevelopment: env.isDevelopment,
  isProduction: env.isProduction,
  isTest: env.isTest,
  databaseUrl: env.DATABASE_URL,
  shadowDatabaseUrl: env.SHADOW_DATABASE_URL,
  rootDatabaseUrl: env.ROOT_DATABASE_URL,
} as const;
