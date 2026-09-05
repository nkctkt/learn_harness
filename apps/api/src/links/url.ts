import { z } from "zod";

/**
 * ユーザーが保存する URL の正規化と検証。
 * - http / https 以外は拒否(javascript: や file: を DB に入れない)
 * - fragment(#...)は同一ページなので落とす
 * - host は大文字小文字を区別しないので小文字にする
 * 公開ホストかどうか(SSRF 対策)は enricher が取得する直前にも再検証する(Phase 3)。
 */
const urlSchema = z.string().trim().min(1, "url is required").max(2048, "url is too long").url();

export type NormalizedUrl = { href: string; host: string };

export function normalizeUrl(input: string): NormalizedUrl {
  const parsed = new URL(urlSchema.parse(input));
  if (parsed.protocol !== "http:" && parsed.protocol !== "https:") {
    throw new Error(`unsupported protocol: ${parsed.protocol}`);
  }
  parsed.hash = "";
  parsed.hostname = parsed.hostname.toLowerCase();
  return { href: parsed.href, host: parsed.hostname };
}

const PRIVATE_V4 = [
  /^127\./,
  /^10\./,
  /^192\.168\./,
  /^172\.(1[6-9]|2\d|3[01])\./,
  /^169\.254\./,
  /^0\./,
];

/** ループバック・プライベート・リンクローカルを「公開ホストではない」と判定する。DNS 解決前の静的判定。 */
export function isPublicHost(host: string): boolean {
  const h = host.replace(/^\[|\]$/g, "").toLowerCase();
  if (h === "localhost" || h.endsWith(".localhost") || h.endsWith(".internal")) return false;
  if (h === "::1" || h.startsWith("fe80:") || h.startsWith("fc") || h.startsWith("fd"))
    return false;
  return !PRIVATE_V4.some((re) => re.test(h));
}
