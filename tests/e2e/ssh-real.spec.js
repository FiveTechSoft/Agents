// REAL SSH via ssh2 gateway mode — LOCAL ONLY (password stays in this machine).
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

test('/ssh real server, password auth (ssh2 mode)', async ({ page }) => {
  test.setTimeout(90000);
  const pass = process.env.SSH_PASS;
  if (!pass) throw new Error('Set SSH_PASS env var');
  await page.addInitScript(() => { try { localStorage.setItem('ssh_proxy', 'ws://127.0.0.1:8080'); } catch (e) {} });
  await page.goto('/index.html');
  const input = page.locator('#prompt');
  await expect(input).toBeVisible({ timeout: 20000 });

  await input.fill('/ssh fivetech@84.126.81.81 2222 ' + pass);
  await input.press('Enter');
  await expect(page.getByText(/SSH: fivetech@84\.126\.81\.81:2222/)).toBeVisible({ timeout: 15000 });
  await expect(page.locator('.ssh-status')).toHaveText(/conectado|connected/i, { timeout: 25000 });

  // ssh2 mode: straight into a remote shell
  await expect.poll(() => termText(page), { timeout: 30000 }).toMatch(/\$\s*$|fivetech@/);

  await input.fill('whoami');
  await input.press('Enter');
  await expect.poll(() => termText(page), { timeout: 20000 }).toContain('fivetech');

  await input.fill('/exit');
  await input.press('Enter');
});
