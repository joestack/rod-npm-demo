# rod-npm-demo

A small Node.js / Express demo app ([`server.mjs`](server.mjs)) used to showcase a **JFrog-secured CI/CD pipeline** on GitHub Actions: build → scan → publish → containerize, plus pull-request security scanning with **Frogbot v3**.

The app itself is a fork of [benc-uk/nodejs-demoapp](https://github.com/benc-uk/nodejs-demoapp); the interesting part here is the security tooling around it.

---

## Platform setup

| Setting | Value |
|---|---|
| JFrog platform | `https://solengeu.jfrog.io` (GitHub repo/org var `JF_URL`) |
| Auth | OIDC, provider name `joern-github` (no stored tokens in the build) |
| npm resolve / deploy | `joern-npm-remote` → `joern-npm-local` |
| Build artifact (tarball) | `joern-generic-local` |
| Docker base / target | `joern-docker-remote` → `joern-docker-local` |
| Build info | `joern-demo-npm` |
| Frogbot Git token | secret `JF_GIT_TOKEN` |

---

## Workflows

### 1. Build pipeline — [`.github/workflows/workflow.yml`](.github/workflows/workflow.yml)

Runs on push to `main` (and `workflow_dispatch`):

1. **OIDC login** to JFrog (`setup-jfrog-cli`, pinned to `2.106.0`).
2. **Source scan** — `jf audit` with SCA + Contextual Analysis + Secrets + SAST (`--static-sca --sbom`). Results go to the JFrog Platform and a `scan-result-audit` artifact.
3. **Install & test** — `jf npm install` against `joern-npm-remote`, start the app, run the `httpyac` tests.
4. **Publish** the npm package to `joern-npm-local`.
5. **Package once** — prune dev deps, tar the app (`source + node_modules`) into `app.tar.gz`, **upload it to `joern-generic-local`**, then **download it back** into the Docker build context. The image is assembled from the published artifact via `ADD app.tar.gz` in the [`Dockerfile`](Dockerfile) — no second `npm install`.
6. **Docker** — `jf docker build` / `scan` / `push` to `joern-docker-local` as `myapp-image:<run#>`.
7. **Build-info** — collect env + VCS, publish, and `jf build-scan`.

> The base image is resolved through a **Curated** remote, so a first-ever pull may briefly 403 with *"curation on-demand in progress"* until the package is catalogued.

### 2. Pull-request scan — [`.github/workflows/frogbot-scan-pull-request.yml`](.github/workflows/frogbot-scan-pull-request.yml)

**Frogbot v3** scans every PR (`opened`/`synchronize`/`reopened`), comments findings inline, and fails on critical issues (`JF_FAIL: true`, `JF_MIN_SEVERITY: critical`). It authenticates via the same OIDC provider and runs behind the `frogbot` GitHub environment (a reviewer must approve before a PR is scanned).

### Consuming the image

See [`README_docker.md`](README_docker.md) for how to log in, pull, and run `myapp-image`.

---

## Demo scenarios

These are the scripted flows this repo exists to demonstrate (source notes in [`demo.txt`](demo.txt)). Each uses a throwaway branch + PR so Frogbot and the policies fire.

### Branch & PR flow

```bash
git checkout -b test
# ...make a change (see scenarios below)...
git add -A && git commit -m "test"
git push origin test
gh pr create --title "test" --body "test"

# cleanup
git checkout main
git branch -D test
git push origin --delete test
git fetch --prune
```

### Scenario A — Curation (block malicious / uncurated packages)

Add a known-bad dependency to [`package.json`](package.json), refresh the lockfile, and push:

```jsonc
"jfrog-curation-malicious-dummy": "1.0.0",
"bidirectional-adapter": "1.2.5"
```

```bash
npm i --package-lock-only   # or: npm install
```

The **Curation** service blocks resolution of packages that aren't approved in the catalog — the install/build is rejected before the dependency ever enters the repo.

### Scenario B — Xray Watch (fail on policy via version constraints)

Pin a dependency to a version that violates an active Xray policy/watch, then flip it to a compliant range:

```jsonc
"morgan": "1.9.0"      // ❌ fails the watch policy
"morgan": "^1.10.0"    // ✅ compliant
```

On a PR, **Frogbot** comments the violation and fails the check; in the build pipeline, an active *Fail build* rule makes `jf audit` / `jf build-scan` exit non-zero.

---

## Local development

```bash
npm install
npm start        # http://localhost:3000
npm test         # httpyac tests in tests/
npm run lint
```

test2