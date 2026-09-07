import { z } from "zod";

/**
 * api が他サービスに期待する応答の形(consumer 側の契約)。
 * - clients.ts はこれで実行時に検証する
 * - scripts/export-contracts.ts が JSON Schema として contracts/ に書き出す
 * - shortener(Go)/ enricher(Python)のテストがその JSON Schema で自分の応答を検証する
 * 変更したら `pnpm --filter @shelf/api contracts:export` を実行し、差分をコミットする(CI が drift を検出する)。
 */
export const enrichResponse = z
  .object({
    title: z.string().nullable(),
    description: z.string().nullable().optional(),
    image: z.string().nullable().optional(),
    site_name: z.string().nullable().optional(),
  })
  .passthrough();

export const shortenResponse = z
  .object({
    code: z.string().regex(/^[a-z2-9]{7}$/),
    target: z.string().url(),
  })
  .passthrough();

export const contracts = {
  "enricher.enrich.response": enrichResponse,
  "shortener.links.response": shortenResponse,
} as const;
