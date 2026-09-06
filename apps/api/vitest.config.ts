import { defineConfig } from "vitest/config";

// 結合テスト(*.integration.test.ts)は Docker が必要で数秒かかるため、INTEGRATION=1 の時だけ含める。
// verify.sh の全体モード(CI / Stop hook)は test:coverage 経由で INTEGRATION=1 を立てる。
const integration = process.env.INTEGRATION === "1";

export default defineConfig({
  test: {
    include: integration
      ? ["src/**/*.test.ts"]
      : ["src/**/*.test.ts", "!src/**/*.integration.test.ts"],
    testTimeout: 30_000,
    coverage: {
      provider: "v8",
      include: ["src/**/*.ts"],
      exclude: ["src/**/*.test.ts", "src/index.ts"],
      reporter: ["text", "json-summary"],
    },
  },
});
