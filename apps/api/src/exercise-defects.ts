// EXERCISE: Phase 1 静的ゲートの検出確認。各行がどの層(Biome / tsc)で止まるかを見る。
import { readFile } from "node:fs/promises";
import { Hono } from "hono";

export const untyped: any = JSON.parse("{}"); // (1) any → Biome noExplicitAny。tsc は通す
export const count: number = "not a number"; // (2) 型エラー → tsc。Biome は通す

export function loadConfig(path: string) {
  readFile(path, "utf8"); // (3) await 忘れ(floating promise)→ Biome が型無しで拾えるか?
  return "loaded";
}

export function greet(name: string) {
  const unusedLocal = name.toUpperCase(); // (4) 未使用変数 → Biome noUnusedVariables
  return `hello ${name}`
}
