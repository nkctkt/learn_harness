// zod スキーマを JSON Schema(draft 2020-12)として contracts/ に書き出す。
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { z } from "zod";
import { contracts } from "../src/links/contracts.js";

const outDir = fileURLToPath(new URL("../../../contracts/", import.meta.url));
mkdirSync(outDir, { recursive: true });
const check = process.argv.includes("--check");
let drift = false;
for (const [name, schema] of Object.entries(contracts)) {
  const json = `${JSON.stringify(
    {
      $schema: "https://json-schema.org/draft/2020-12/schema",
      $id: `${name}.schema.json`,
      ...z.toJSONSchema(schema),
    },
    null,
    2,
  )}\n`;
  const file = `${outDir}${name}.schema.json`;
  if (check) {
    let current = "";
    try {
      current = readFileSync(file, "utf8");
    } catch {
      /* missing = drift */
    }
    if (current !== json) {
      drift = true;
      console.error(
        `contract drift: ${file} は src/links/contracts.ts と一致しません。contracts:export を実行してください`,
      );
    }
  } else {
    writeFileSync(file, json);
    console.info(`wrote ${file}`);
  }
}
if (drift) process.exit(1);
