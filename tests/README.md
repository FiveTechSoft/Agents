# Tests E2E (Playwright)

Black-box tests against the deployed Agents Web app (or a local build): page load,
console errors, simulated shell, disk panel, slash-command cards, prompt history
persistence and Markdown preview.

## Setup (once)

```sh
npm i playwright
npx playwright install chromium firefox
```

## Run

```sh
# against the live site (default: chromium)
node tests/test-agents.mjs
node tests/test-agents.mjs firefox

# against a local build (serve docs/ first)
npx http-server docs -p 8123
node tests/test-agents.mjs firefox http://127.0.0.1:8123/
```

Exits with a PASS/FAIL line per check plus all console/page errors captured
from the very first navigation (including the COI service-worker reload).
Firefox matters: it has no `COEP: credentialless` support, so it exercises the
`require-corp` path of `coi-serviceworker`.
