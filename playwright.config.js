// @ts-check
const { defineConfig } = require('@playwright/test');

module.exports = defineConfig({
  testDir: 'tests/e2e',
  timeout: 30000,
  retries: 0,
  use: {
    channel: 'msedge',            // uses the system Edge — no browser download needed
    baseURL: 'http://127.0.0.1:8931',
    viewport: { width: 1280, height: 900 },
  },
  webServer: {
    command: 'python -m http.server 8931 --directory docs',
    port: 8931,
    reuseExistingServer: true,
  },
});
