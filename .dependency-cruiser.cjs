/**
 * アーキテクチャ規約を機械検査する。lint も型も見ない「どのモジュールがどこに依存してよいか」。
 *   apps/api:  links/routes → links/repository(インターフェース) と links/url のみ。db/ を直接 import しない。
 *              db/ は links/ を import しない(下位層は上位層を知らない)。
 *   apps/web:  lib/ は React に依存しない(純粋関数だけ)。
 *   共通:      循環依存なし、テストファイルを本番コードから import しない。
 */
/** @type {import('dependency-cruiser').IConfiguration} */
module.exports = {
  forbidden: [
    {
      name: "no-circular",
      severity: "error",
      comment: "循環依存は初期化順とテスト容易性を壊す",
      from: {},
      to: { circular: true },
    },
    {
      name: "no-test-import-from-prod",
      severity: "error",
      comment: "本番コードからテストファイルを import しない",
      from: { pathNot: "\\.test\\.tsx?$" },
      to: { path: "\\.test\\.tsx?$" },
    },
    {
      name: "api-routes-must-not-touch-db",
      severity: "error",
      comment:
        "HTTP 層は Repository インターフェース経由で DB に触る。routes から db/ を直接 import しない",
      from: { path: "^apps/api/src/links/routes\\.ts$" },
      to: { path: "^apps/api/src/db/" },
    },
    {
      name: "api-db-is-a-leaf",
      severity: "error",
      comment: "db/ は上位層(links/, app.ts)を知らない",
      from: { path: "^apps/api/src/db/" },
      to: { path: "^apps/api/src/(links|app)" },
    },
    {
      name: "web-lib-is-framework-free",
      severity: "error",
      comment: "web/src/lib は React に依存しない純粋関数だけ(単体テストの容易さと再利用のため)",
      from: { path: "^apps/web/src/lib/" },
      to: { path: "^react|react-dom" },
    },
  ],
  options: {
    doNotFollow: { path: "node_modules" },
    tsPreCompilationDeps: true,
    exclude: { path: "node_modules|\\.d\\.ts$" },
    reporterOptions: { text: { highlightFocused: true } },
  },
};
