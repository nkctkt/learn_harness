import { expect, test } from "@playwright/test";

type Item = {
  id: number;
  href: string;
  host: string;
  title: string | null;
  shortCode: string | null;
  createdAt: string;
};

test.beforeEach(async ({ page }) => {
  const items: Item[] = [];
  await page.route("**/api/health", (route) =>
    route.fulfill({ json: { status: "ok", service: "api" } }),
  );
  await page.route("**/api/links", async (route) => {
    if (route.request().method() === "POST") {
      const body = route.request().postDataJSON() as { url: string };
      if (body.url.includes("127.0.0.1"))
        return route.fulfill({ status: 400, json: { error: "host is not public" } });
      const item: Item = {
        id: items.length + 1,
        href: body.url,
        host: new URL(body.url).host,
        title: "Mocked title",
        shortCode: "abc2345",
        createdAt: new Date().toISOString(),
      };
      items.unshift(item);
      return route.fulfill({ status: 201, json: { item } });
    }
    return route.fulfill({ json: { items } });
  });
});

test("shows api health, saves a link and lists it with title and short code", async ({ page }) => {
  await page.goto("/");
  await expect(page.getByTestId("health")).toHaveText("api: ok (api)");
  await page.getByPlaceholder("https://example.com/article").fill("https://example.com/docs");
  await page.getByRole("button", { name: "Save" }).click();
  await expect(page.getByTestId("links").getByRole("listitem")).toHaveCount(1);
  await expect(page.getByRole("link", { name: "Mocked title (abc2345)" })).toBeVisible();
});

test("surfaces the API's rejection for a non-public host", async ({ page }) => {
  await page.goto("/");
  await page.getByPlaceholder("https://example.com/article").fill("http://127.0.0.1:8080/admin");
  await page.getByRole("button", { name: "Save" }).click();
  await expect(page.getByTestId("error")).toHaveText("host is not public");
  await expect(page.getByTestId("links").getByRole("listitem")).toHaveCount(0);
});
