import { useEffect, useState } from "react";
import { type Health, healthLabel } from "./lib/healthLabel";

export function App() {
  const [health, setHealth] = useState<Health | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    fetch("/api/health")
      .then((r) => r.json() as Promise<Health>)
      .then(setHealth)
      .catch((e: unknown) => setError(e instanceof Error ? e.message : String(e)));
  }, []);

  return (
    <main>
      <h1>Reading Shelf</h1>
      <p>api: {healthLabel(health, error)}</p>
    </main>
  );
}
