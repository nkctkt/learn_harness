export type LinkItem = {
  id: number;
  href: string;
  host: string;
  title: string | null;
  shortCode: string | null;
  createdAt: string;
};

type ApiError = { error: string };

/** API 呼び出しを 1 箇所に。fetch を注入できるのでテストで差し替えられる。 */
export function createApi(fetchFn: typeof fetch = fetch, base = "/api") {
  return {
    async list(): Promise<LinkItem[]> {
      const res = await fetchFn(`${base}/links`);
      if (!res.ok) throw new Error(`list failed: ${res.status}`);
      return ((await res.json()) as { items: LinkItem[] }).items;
    },
    async create(
      url: string,
      title?: string,
    ): Promise<{ ok: true; item: LinkItem } | { ok: false; error: string }> {
      const res = await fetchFn(`${base}/links`, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify(title ? { url, title } : { url }),
      });
      const body = (await res.json()) as { item?: LinkItem } & Partial<ApiError>;
      if (!res.ok || !body.item) return { ok: false, error: body.error ?? `http ${res.status}` };
      return { ok: true, item: body.item };
    },
  };
}

/** 一覧表示用のラベル。title が無ければ host、short code があれば付ける。 */
export function linkLabel(item: Pick<LinkItem, "title" | "host" | "shortCode">): string {
  const name = item.title?.trim() || item.host;
  return item.shortCode ? `${name} (${item.shortCode})` : name;
}
