import { describe, expect, it } from "vitest";
import { healthLabel } from "./healthLabel";

describe("healthLabel", () => {
  it("shows loading before the response arrives", () => {
    expect(healthLabel(null, null)).toBe("loading…");
  });
  it("prefers the error over a stale health value", () => {
    expect(healthLabel({ status: "ok", service: "api" }, "boom")).toBe("error: boom");
  });
  it("formats a healthy response", () => {
    expect(healthLabel({ status: "ok", service: "api" }, null)).toBe("ok (api)");
  });
});
