import { describe, expect, it } from "vitest";
import { isPublicHost, normalizeUrl } from "./url.js";

describe("normalizeUrl", () => {
  it("lowercases the host and drops the fragment", () => {
    expect(normalizeUrl("https://Example.COM/a#top")).toEqual({
      href: "https://example.com/a",
      host: "example.com",
    });
  });

  it("keeps query strings because they identify different resources", () => {
    expect(normalizeUrl("https://example.com/s?q=1").href).toBe("https://example.com/s?q=1");
  });

  it.each(["javascript:alert(1)", "file:///etc/passwd", "ftp://example.com/x"])(
    "rejects non-http protocol %s",
    (input) => {
      expect(() => normalizeUrl(input)).toThrow();
    },
  );

  it.each(["", "   ", "not a url", `https://${"a".repeat(2050)}.com`])(
    "rejects malformed input %j",
    (input) => {
      expect(() => normalizeUrl(input)).toThrow();
    },
  );
});

describe("isPublicHost", () => {
  // test-reviewer の指摘 (重大 4): 先頭アンカーが外れても落ちるように、"127." 等を途中に含む公開ホストを入れる
  it.each([
    "example.com",
    "8.8.8.8",
    "sub.example.co.jp",
    "172.32.0.1",
    "abc.127.example.com",
    "10.example.net",
    "172.15.0.1",
  ])("accepts public host %s", (host) => {
    expect(isPublicHost(host)).toBe(true);
  });

  it.each([
    "localhost",
    "api.localhost",
    "db.internal",
    "127.0.0.1",
    "10.1.2.3",
    "192.168.0.10",
    "172.16.5.5",
    "172.25.0.1",
    "172.31.255.255",
    "169.254.169.254",
    "::1",
    "[::1]",
    "fd12::1",
    "fc00::1",
    "fe80::1",
    "[fe80::1%25eth0]",
  ])("rejects non-public host %s", (host) => {
    expect(isPublicHost(host)).toBe(false);
  });
});
