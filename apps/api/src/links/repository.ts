import { desc, eq } from "drizzle-orm";
import type { Db } from "../db/client.js";
import { type Link, links } from "../db/schema.js";

export type LinkRepository = {
  list(): Promise<Link[]>;
  findByHref(href: string): Promise<Link | undefined>;
  create(input: { href: string; host: string; title?: string | null }): Promise<Link>;
};

/** Drizzle のクエリビルダを使う。値は常にパラメータとして渡され、SQL に文字列連結されない。 */
export function createLinkRepository(db: Db): LinkRepository {
  return {
    async list() {
      return db.select().from(links).orderBy(desc(links.createdAt), desc(links.id));
    },
    async findByHref(href) {
      const rows = await db.select().from(links).where(eq(links.href, href)).limit(1);
      return rows[0];
    },
    async create(input) {
      const rows = await db
        .insert(links)
        .values({ href: input.href, host: input.host, title: input.title ?? null })
        .returning();
      const row = rows[0];
      if (!row) throw new Error("insert returned no row");
      return row;
    },
  };
}
