import { sql } from "drizzle-orm";

declare const db: { execute(q: unknown): Promise<unknown> };
declare const client: { unsafe(q: string): Promise<unknown> };
declare const userInput: string;

export async function bad1() {
  // ruleid: shelf.drizzle-sql-raw-interpolation
  return db.execute(sql.raw(`select * from links where host = '${userInput}'`));
}
export async function bad2() {
  // ruleid: shelf.drizzle-sql-raw-interpolation
  return db.execute(sql.raw("select * from links where host = '" + userInput + "'"));
}
export async function bad3() {
  // ruleid: shelf.postgres-js-unsafe
  return client.unsafe(`select ${userInput}`);
}
export async function good1() {
  // ok: shelf.drizzle-sql-raw-interpolation
  return db.execute(sql`select * from links where host = ${userInput}`);
}
export async function good2() {
  // ok: shelf.drizzle-sql-raw-interpolation
  return db.execute(sql.raw("select 1"));
}
