import { pgTable, serial, text, timestamp, uniqueIndex } from "drizzle-orm/pg-core";

export const links = pgTable(
  "links",
  {
    id: serial("id").primaryKey(),
    href: text("href").notNull(),
    host: text("host").notNull(),
    title: text("title"),
    createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
  },
  (t) => [uniqueIndex("links_href_unique").on(t.href)],
);

export type Link = typeof links.$inferSelect;
export type NewLink = typeof links.$inferInsert;
