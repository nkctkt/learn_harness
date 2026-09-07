import { z } from "zod";

/**
 * ユーザーが保存する URL の正規化と検証。
 * - http / https 以外は拒否(javascript: や file: を DB に入れない)
 * - fragment(#...)は同一ページなので落とす
 * - host は大文字小文字を区別しないので小文字にする
 * 公開ホストかどうか(SSRF 対策)は enricher が取得する直前にも再検証する(名前解決後の IP で)。
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

const IPV4_LITERAL = /^\d{1,3}(\.\d{1,3}){3}$/;

/**
 * ループバック・プライベート・リンクローカルを「公開ホストではない」と判定する。DNS 解決前の静的判定。
 * IPv4 の私設レンジ判定は IP リテラルにだけ適用する。"10.example.net" のようなホスト名を誤って弾いていた
 * バグを、test-reviewer の指摘で追加したテストが見つけた(Exercise 10)。
 */
export function isPublicHost(host: string): boolean {
  const h = host.replace(/^\[|\]$/g, "").toLowerCase();
  if (h === "localhost" || h.endsWith(".localhost") || h.endsWith(".internal")) return false;
  if (h.includes(":")) {
    // IPv6 リテラル。zone id(%eth0)は判定から外す
    const v6 = h.split("%")[0] ?? h;
    return !(v6 === "::1" || v6.startsWith("fe80:") || v6.startsWith("fc") || v6.startsWith("fd"));
  }
  if (IPV4_LITERAL.test(h)) return !PRIVATE_V4.some((re) => re.test(h));
  return true;
}
