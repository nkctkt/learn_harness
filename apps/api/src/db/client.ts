import { fileURLToPath } from "node:url";
import { drizzle } from "drizzle-orm/postgres-js";
import { migrate } from "drizzle-orm/postgres-js/migrator";
import postgres from "postgres";
import * as schema from "./schema.js";

export type Db = ReturnType<typeof createDb>;

/** 接続文字列は環境変数から。コードや設定ファイルに資格情報を書かない。 */
export function createDb(databaseUrl: string) {
  const client = postgres(databaseUrl, { max: 5 });
  return drizzle(client, { schema });
}

/** drizzle/ 配下の SQL マイグレーションを適用する。起動時とテスト前に呼ぶ。 */
export async function migrateDb(
  db: Db,
  // URL.pathname は percent-encode されるので使わない(日本語やスペースを含むパスで壊れる)
  migrationsFolder = fileURLToPath(new URL("../../drizzle/", import.meta.url)),
) {
  await migrate(db, { migrationsFolder });
}
