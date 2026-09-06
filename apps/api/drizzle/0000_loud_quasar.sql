CREATE TABLE "links" (
	"id" serial PRIMARY KEY NOT NULL,
	"href" text NOT NULL,
	"host" text NOT NULL,
	"title" text,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE UNIQUE INDEX "links_href_unique" ON "links" USING btree ("href");