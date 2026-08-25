// /ssh end-to-end: browser -> WebSocket gateway -> TCP -> xterm buffer
const { test, expect } = require('@playwright/test');

async function termText(page) {
  return page.evaluate(() => {
    const t = (typeof activeSsh !== 'undefined' && activeSsh) ? activeSsh.term : null;
    if (!t) return '';
    let out = '';
    for (let i = 0; i < t.rows; i++) out += (t.buffer.active.getLine(i)?.translateToString() || '') + '\n';
    return out;
  });
}

test('/ssh connects through the gateway and renders the remote banner', async ({ page }) => {
  test.setTimeout(60000);
  await page.addInitScript(() => { try { localStorage.setItem('ssh_proxy', 'ws://127.0.0.1:8080'); } catch (e) {} });
  await page.goto('/index.html');
  const input = page.locator('#prompt');
  await expect(input).toBeVisible({ timeout: 20000 });

  await input.fill('/ssh test@127.0.0.1 2222');
  await input.press('Enter');
  await expect(page.getByText(/SSH: test@127\.0\.0\.1:2222/)).toBeVisible({ timeout: 15000 });
  await expect(page.locator('.ssh-status')).toHaveText(/conectado|connected/i, { timeout: 15000 });

  // the remote SSH identification string arrives in the terminal buffer
  await expect.poll(() => termText(page), { timeout: 15000 })
    .toContain('SSH-2.0-OpenSSH_AgentsTest');

  // type a command in the prompt -> routed to the SSH session -> echoed by the remote side
  await input.fill('saluda');
  await input.press('Enter');
  await expect.poll(() => termText(page), { timeout: 10000 }).toContain('echo: saluda');

  // disconnect via /exit
  await input.fill('/exit');
  await input.press('Enter');
  await expect(page.getByText(/Sesión SSH cerrada/)).toBeVisible({ timeout: 5000 });
});
