// Every slash command must be wired: no 'Comando desconocido' ever appears.
const { test, expect } = require('@playwright/test');

test.describe.configure({ mode: 'serial' });

test('all slash commands are dispatched correctly', async ({ page }) => {
  test.setTimeout(180000);
  await page.goto('/index.html');
  const input = page.locator('#prompt');
  await expect(input).toBeVisible({ timeout: 20000 });

  const cmds = [
    '/help', '/clear', '/cost', '/compact', '/init', '/key', '/ghtoken',
    '/goal', '/goal objetivo de prueba', '/plan escribe un haiku sobre Harbour',
    '/run', '/loop', '/proxy', '/git', '/action list', '/cron', '/perm',
    '/skill', '/tool', '/sh echo hola', '/share', '/btw una nota',
    "/py print('py ok')", '/cc', '/classify', '/ssh', '/exit',
  ];
  for (const c of cmds) {
    await input.fill(c);
    await input.press('Enter');
    await page.waitForTimeout(c === '/plan escribe un haiku sobre Harbour' ? 15000 : 700);
  }

  const body = await page.locator('#content, main').first().innerText();
  expect(body).not.toContain('Comando desconocido');
});
