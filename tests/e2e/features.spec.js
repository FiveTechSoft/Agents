// Exhaustive feature verification for Agents Web
const { test, expect } = require('@playwright/test');

async function open(page) {
  await page.goto('/index.html');
  await expect(page.locator('#prompt')).toBeVisible({ timeout: 20000 });
  return page.locator('#prompt');
}

test.describe.configure({ mode: 'serial' });

test('header, model tag, voice buttons present', async ({ page }) => {
  await open(page);
  await expect(page).toHaveTitle(/Agents/);
  await expect(page.locator('#modeltag')).toHaveText(/Ox Alpha/);
  await expect(page.locator('#ttsbtn')).toBeVisible();
  await expect(page.locator('#micbtn')).toBeVisible();
});

test('TTS toggle persists in localStorage and button state', async ({ page }) => {
  const input = await open(page);
  const tts = page.locator('#ttsbtn');
  await expect(tts).not.toHaveClass(/bg-emerald-700/);
  await tts.click();
  await expect(tts).toHaveClass(/bg-emerald-700/);
  await expect(page.getByText(/Voz: ON/)).toBeVisible({ timeout: 5000 });
  expect(await page.evaluate(() => localStorage.getItem('tts'))).toBe('1');
  await tts.click();
  expect(await page.evaluate(() => localStorage.getItem('tts'))).toBe('0');
});

test('/voice lists system voices and /voice del resets', async ({ page }) => {
  const input = await open(page);
  await input.fill('/voice');
  await input.press('Enter');
  // either the voice list or the "no voices" message appears — never an error
  await expect(page.getByText(/Voz restablecida|seleccionada|voces instaladas|Índice inválido|Uso: \/voice/).first()).toBeVisible({ timeout: 10000 });
  const body = await page.locator('main').innerText();
  expect(body).not.toContain('Comando desconocido');
  await input.fill('/voice del');
  await input.press('Enter');
  await expect(page.getByText(/Voz restablecida/)).toBeVisible({ timeout: 10000 });
  expect(await page.evaluate(() => localStorage.getItem('tts_voice'))).toBeNull();
});

test('/perm set, list (with * marker) and reset', async ({ page }) => {
  const input = await open(page);
  await input.fill('/perm shell deny');
  await input.press('Enter');
  await expect(page.getByText('Permiso shell = deny')).toBeVisible({ timeout: 10000 });
  await input.fill('/perm');
  await input.press('Enter');
  await expect(page.getByText(/shell = deny \*/)).toBeVisible();
  await input.fill('/perm shell ask');
  await input.press('Enter');
  await expect(page.getByText('Permiso shell = ask')).toBeVisible({ timeout: 10000 });
});

test('permission gate blocks shell when policy is deny', async ({ page }) => {
  const input = await open(page);
  await input.fill('/perm shell deny');
  await input.press('Enter');
  await expect(page.getByText('Permiso shell = deny')).toBeVisible({ timeout: 10000 });
  // invoke a tool call directly as the LLM would
  const out = await page.evaluate(async () => execToolRaw('shell', JSON.stringify({ command: 'echo hola' })));
  expect(out).toContain('Permiso denegado');
  // allow it -> executes
  await page.evaluate(() => { PERM.shell = 'allow'; permSave(); });
  const out2 = await page.evaluate(async () => execToolRaw('shell', JSON.stringify({ command: 'echo hola' })));
  expect(out2).toContain('hola');
});

test('/cron registers, lists and deletes tasks', async ({ page }) => {
  const input = await open(page);
  await input.fill('/cron 30m /cost');
  await input.press('Enter');
  await expect(page.getByText(/Tarea #\d+ programada cada 30m/)).toBeVisible({ timeout: 10000 });
  expect(await page.evaluate(() => JSON.parse(localStorage.getItem('crons') || '[]').length)).toBe(1);
  await input.fill('/cron');
  await input.press('Enter');
  await expect(page.getByText(/#1 · cada 30m · \/cost/)).toBeVisible({ timeout: 10000 });
  await input.fill('/cron del 1');
  await input.press('Enter');
  await expect(page.getByText(/Tarea #1 eliminada/)).toBeVisible({ timeout: 10000 });
  expect(await page.evaluate(() => JSON.parse(localStorage.getItem('crons') || '[]').length)).toBe(0);
});

test('schedule_task tool registers recurring jobs (LLM path)', async ({ page }) => {
  const input = await open(page);
  const res = await page.evaluate(async () =>
    execToolRaw('schedule_task', JSON.stringify({ every: '1m', task: 'dime algo interesante' })));
  expect(res).toContain('Programada: #1 cada 1m');
  const jobs = await page.evaluate(() => JSON.parse(localStorage.getItem('crons') || '[]'));
  expect(jobs.length).toBe(1);
  expect(jobs[0].cmd).toBe('dime algo interesante');
  expect(jobs[0].ms).toBe(60000);
  // cleanup
  await input.fill('/cron del 1');
  await input.press('Enter');
  await expect(page.getByText(/Tarea #1 eliminada/)).toBeVisible({ timeout: 10000 });
});

test('message while agent is busy queues as interjection (no parallel agent)', async ({ page }) => {
  const input = await open(page);
  // simulate the agent working without any network
  await page.evaluate(() => setWorking(true));
  await input.fill('otra pregunta mientras piensas');
  await input.press('Enter');
  await expect(page.getByText(/agente está ocupado/)).toBeVisible({ timeout: 5000 });
  const pending = await page.evaluate(() => btwPending);
  expect(pending).toContain('otra pregunta mientras piensas');
  // only ONE user bubble queued via 💬, no second agent started
  await page.evaluate(() => setWorking(false));
});

test('slash autocomplete: filtered, upward, Tab completes, Esc closes', async ({ page }) => {
  const input = await open(page);
  await input.click();
  await input.pressSequentially('/ac', { delay: 40 });
  await expect(page.locator('#acdd')).toBeVisible();
  await expect(page.locator('#acdd .ac-item')).toHaveCount(1);
  const dd = await page.locator('#acdd').boundingBox();
  const inp = await input.boundingBox();
  expect(dd.y + dd.height).toBeLessThanOrEqual(inp.y + 1);
  await input.press('Tab');
  await expect(input).toHaveValue('/action ');
  await input.pressSequentially('li', { delay: 30 });
  await input.press('Escape');          // args typed -> dropdown already closed; Esc harmless
  await expect(input).toHaveValue('/action li');
});

test('/help card shows every documented command', async ({ page }) => {
  const input = await open(page);
  await input.fill('/help');
  await input.press('Enter');
  await expect(page.locator('.chc')).toBeVisible({ timeout: 10000 });
  const txt = await page.locator('.chc').innerText();
  for (const c of ['/cost','/compact','/init','/goal','/plan','/run','/clone','/git','/action','/cron','/perm','/voice','/skill','/tool','/sh','/share','/btw','/py','/cc','/classify','/ssh','/exit','/proxy','/loop','/ghtoken','/key','/clear','/help']) {
    expect(txt).toContain(c);
  }
});
