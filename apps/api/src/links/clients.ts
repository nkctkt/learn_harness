import { enrichResponse, shortenResponse } from "./contracts.js";

/**
 * 他サービスへの呼び出し。どちらも「無くても保存はできる」補助機能なので、
 * 失敗・タイムアウト・契約不一致は undefined に畳んで呼び出し側を止めない(ログには残す)。
 * 応答は zod で検証する: 相手サービスの変更で形が変わった時に、黙って undefined を入れるのではなく検出できる。
 */
export type Enricher = { enrich(href: string): Promise<{ title?: string } | undefined> };
export type Shortener = { shorten(href: string): Promise<string | undefined> };

type Logger = { warn(msg: string, meta?: Record<string, unknown>): void };

type Options = { baseUrl: string; timeoutMs?: number; log?: Logger; fetchFn?: typeof fetch };

async function postJson(opts: Options, path: string, body: unknown): Promise<unknown> {
  const fetchFn = opts.fetchFn ?? fetch;
  const res = await fetchFn(new URL(path, opts.baseUrl), {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(body),
    signal: AbortSignal.timeout(opts.timeoutMs ?? 3000),
  });
  if (!res.ok) throw new Error(`${path}: http ${res.status}`);
  return res.json();
}

export function httpEnricher(opts: Options): Enricher {
  return {
    async enrich(href) {
      try {
        const parsed = enrichResponse.safeParse(await postJson(opts, "/enrich", { url: href }));
        if (!parsed.success) {
          opts.log?.warn("enricher: unexpected response shape", { issues: parsed.error.issues });
          return undefined;
        }
        return parsed.data.title ? { title: parsed.data.title } : {};
      } catch (e) {
        opts.log?.warn("enricher: unavailable", {
          error: e instanceof Error ? e.message : String(e),
        });
        return undefined;
      }
    },
  };
}

export function httpShortener(opts: Options): Shortener {
  return {
    async shorten(href) {
      try {
        const parsed = shortenResponse.safeParse(await postJson(opts, "/links", { target: href }));
        if (!parsed.success) {
          opts.log?.warn("shortener: unexpected response shape", { issues: parsed.error.issues });
          return undefined;
        }
        return parsed.data.code;
      } catch (e) {
        opts.log?.warn("shortener: unavailable", {
          error: e instanceof Error ? e.message : String(e),
        });
        return undefined;
      }
    },
  };
}

/** 依存サービス無しで動かす時(テスト、ローカル最小構成)の実装。 */
export const noopEnricher: Enricher = { enrich: () => Promise.resolve(undefined) };
export const noopShortener: Shortener = { shorten: () => Promise.resolve(undefined) };
