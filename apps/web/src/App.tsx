import { type FormEvent, useCallback, useEffect, useState } from "react";
import { createApi, type LinkItem, linkLabel } from "./lib/api";
import { type Health, healthLabel } from "./lib/healthLabel";

const api = createApi();

export function App() {
  const [health, setHealth] = useState<Health | null>(null);
  const [healthError, setHealthError] = useState<string | null>(null);
  const [items, setItems] = useState<LinkItem[]>([]);
  const [url, setUrl] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  const refresh = useCallback(async () => {
    try {
      setItems(await api.list());
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    }
  }, []);

  useEffect(() => {
    fetch("/api/health")
      .then((r) => r.json() as Promise<Health>)
      .then(setHealth)
      .catch((e: unknown) => setHealthError(e instanceof Error ? e.message : String(e)));
    void refresh();
  }, [refresh]);

  async function onSubmit(ev: FormEvent) {
    ev.preventDefault();
    setBusy(true);
    setError(null);
    const r = await api.create(url);
    setBusy(false);
    if (!r.ok) {
      setError(r.error);
      return;
    }
    setUrl("");
    await refresh();
  }

  return (
    <main>
      <h1>Reading Shelf</h1>
      <p data-testid="health">api: {healthLabel(health, healthError)}</p>
      <form
        onSubmit={(ev) => {
          void onSubmit(ev);
        }}
        aria-label="add link"
      >
        <input
          type="url"
          name="url"
          placeholder="https://example.com/article"
          value={url}
          onChange={(e) => setUrl(e.target.value)}
          required
        />
        <button type="submit" disabled={busy}>
          Save
        </button>
      </form>
      {error && (
        <p role="alert" data-testid="error">
          {error}
        </p>
      )}
      <ul data-testid="links">
        {items.map((it) => (
          <li key={it.id}>
            <a href={it.href}>{linkLabel(it)}</a>
          </li>
        ))}
      </ul>
    </main>
  );
}
