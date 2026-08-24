// Agents Web — smoke tests for https://fivetechsoft.github.io/Agents/
const { test, expect } = require('@playwright/test');

test('page loads with header and model tag', async ({ page }) => {
  await page.goto('/index.html');
  await expect(page).toHaveTitle(/Agents/);
  await expect(page.locator('#prompt')).toBeVisible();
  await expect(page.locator('#modeltag')).toHaveText(/Ox Alpha/);
});

test('slash autocomplete opens with filtered options', async ({ page }) => {
  await page.goto('/index.html');
  await expect(page.locator('#prompt')).toBeVisible();
  const input = page.locator('#prompt');
  await input.click();
  await input.pressSequentially('/c', { delay: 50 });
  await expect(page.locator('#acdd')).toBeVisible();
  const items = page.locator('#acdd .ac-item');
  await expect(items).toHaveCount(7);            // clear, cost, compact, clone, cc, classify, cron
  await expect(items.first()).toContainText('/clear');
});

test('/help opens the commands card', async ({ page }) => {
  await page.goto('/index.html');
  await expect(page.locator('#prompt')).toBeVisible();
  const input = page.locator('#prompt');
  await input.fill('/help');
  await input.press('Enter');
  await expect(page.locator('.chc')).toBeVisible({ timeout: 10000 });
});

test('/perm lists tool policies', async ({ page }) => {
  await page.goto('/index.html');
  await expect(page.locator('#prompt')).toBeVisible();
  const input = page.locator('#prompt');
  await input.fill('/perm');
  await input.press('Enter');
  await expect(page.getByText('write_file = ask')).toBeVisible({ timeout: 10000 });
});
