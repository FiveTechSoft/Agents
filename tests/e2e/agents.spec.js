// Agents Web — full feature verification
const { test, expect } = require('@playwright/test');

async function open(page) {
  await page.goto('/index.html');
  await expect(page.locator('#prompt')).toBeVisible({ timeout: 20000 });
  const input = page.locator('#prompt');
  return input;
}

test('page loads: header, model tag, voice buttons', async ({ page }) => {
  const input = await open(page);
  await expect(page).toHaveTitle(/Agents/);
  await expect(page.locator('#modeltag')).toHaveText(/Ox Alpha/);
  await expect(page.locator('#ttsbtn')).toBeVisible();
  await expect(page.locator('#micbtn')).toBeVisible();
  await expect(input).toHaveValue('');
});

test('TTS toggle persists state on the button', async ({ page }) => {
  const input = await open(page);
  const tts = page.locator('#ttsbtn');
  await expect(tts).not.toHaveClass(/bg-emerald-700/);
  await tts.click();
  await expect(tts).toHaveClass(/bg-emerald-700/);
  // a tool() message confirms the change
  await expect(page.getByText(/Voz: ON/)).toBeVisible({ timeout: 5000 });
  await tts.click();
  await expect(tts).not.toHaveClass(/bg-emerald-700/);
});

test('slash autocomplete: filtered, opens upward, Tab completes', async ({ page }) => {
  const input = await open(page);
  await input.click();
  await input.pressSequentially('/ac', { delay: 40 });
  await expect(page.locator('#acdd')).toBeVisible();
  const items = page.locator('#acdd .ac-item');
  await expect(items).toHaveCount(1);                       // only /action matches /ac
  await expect(items.first()).toContainText('/action');
  const dd = await page.locator('#acdd').boundingBox();
  const inp = await input.boundingBox();
  expect(dd.y + dd.height).toBeLessThanOrEqual(inp.y + 1); // above the input
  await input.press('Tab');                                // complete it
  await expect(input).toHaveValue('/action ');
  await expect(page.locator('#acdd')).toBeHidden();
});

test('/perm get and set policies', async ({ page }) => {
  const input = await open(page);
  await input.fill('/perm shell deny');
  await input.press('Enter');
  await expect(page.getByText('Permiso shell = deny')).toBeVisible({ timeout: 10000 });
  await input.fill('/perm');
  await input.press('Enter');
  await expect(page.getByText(/write_file = ask/)).toBeVisible();
  await expect(page.getByText(/shell = deny \*/)).toBeVisible();
  await input.fill('/perm shell ask');
  await input.press('Enter');
  await expect(page.getByText('Permiso shell = ask')).toBeVisible({ timeout: 10000 });
});

test('/cron lists usage and registers + deletes a task', async ({ page }) => {
  const input = await open(page);
  await input.fill('/cron');
  await input.press('Enter');
  await expect(page.getByText(/Sin tareas programadas|cada /).first()).toBeVisible({ timeout: 10000 });
  await input.fill('/cron 30m /cost');
  await input.press('Enter');
  await expect(page.getByText(/Tarea #\d+ programada cada 30m/)).toBeVisible({ timeout: 10000 });
  await input.fill('/cron del 1');
  await input.press('Enter');
  await expect(page.getByText(/Tarea #1 eliminada/)).toBeVisible({ timeout: 10000 });
});

test('/action list queries the live repo workflows', async ({ page }) => {
  const input = await open(page);
  await input.fill('/action list');
  await input.press('Enter');
  await expect(page.getByText(/Workflows en FiveTechSoft\/Agents|sin workflows/)).toBeVisible({ timeout: 20000 });
});

test('/help card includes the new commands', async ({ page }) => {
  const input = await open(page);
  await input.fill('/help');
  await input.press('Enter');
  await expect(page.locator('.chc')).toBeVisible({ timeout: 10000 });
  await expect(page.getByText(/GitHub Actions/)).toBeVisible();
  await expect(page.getByText(/Programa tareas/)).toBeVisible();
  await expect(page.getByText(/Permisos/)).toBeVisible();
});
