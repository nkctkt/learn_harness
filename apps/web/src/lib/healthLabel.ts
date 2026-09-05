export type Health = { status: string; service: string };

/** API のヘルス応答を画面表示用の 1 行にする。 */
export function healthLabel(health: Health | null, error: string | null): string {
  if (error) return `error: ${error}`;
  if (!health) return "loading…";
  return `${health.status} (${health.service})`;
}
