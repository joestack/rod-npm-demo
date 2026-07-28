# JFrog MCP Server — Customer Demo Script

Prepared for the MCP Server evaluation demo, based on the customer's 8 requested
scenarios (message received 2026-07-28). Each scenario has two parts:

- **Say/type (MCP client)** — the natural-language prompt to type into the
  connected MCP client (Claude Desktop, VS Code + GitHub Copilot Chat, Claude
  Code, or any other MCP-capable client). This is what the live demo actually
  shows.
- **Cut-and-paste verify** — the equivalent `jf` CLI / `jf api` call. Useful as
  a fallback if a tool call misfires live, and as a credibility check ("here's
  exactly what ran under the hood") for technical stakeholders.

Placeholders (`<REPO>`, `<IMAGE>`, `<PACKAGE>`, …) must be swapped for the
customer's own test-environment values. Where noted, "Verified example"
commands were run against a live test instance during prep and are known-good;
swap in the customer's actual repo/package names before the real demo.

Every `jf` command assumes the session-global setup already run once:

```bash
export JFROG_CLI_USER_AGENT='jfrog-skills/<version> (tool=<client>; model=<model>)'
SID=<resolved-server-id>   # from: jf config show
```

All `jf api` calls below take `--server-id "$SID"` (omitted in examples for
readability — see the skill's server-selection rule).

---

## 1. Package, artifact, Docker image, and PyPI package discovery

**Say/type:**
> "What artifacts are stored in `<REPO>`?"
> "Find all Docker images in `<DOCKER-REPO>`."

**Cut-and-paste verify** (AQL, works for any repo type):

```bash
jf api /artifactory/api/search/aql \
  -X POST -H "Content-Type: text/plain" \
  -d 'items.find({"repo":"<REPO>"}).include("name","path","type").limit(100)'
```

**Verified example** (`joern-docker-local`, 21 items) — swap the repo key:

```bash
jf api /artifactory/api/search/aql \
  -X POST -H "Content-Type: text/plain" \
  -d 'items.find({"repo":"joern-docker-local"}).include("name","path").limit(100)'
```

**Verified PyPI example** — `joern-pypi-local` now holds a real indexed
package (`joern-demo-pkg` 0.1.0), created during prep specifically to cover
this scenario. Same AQL pattern, repo swapped:

```bash
jf api /artifactory/api/search/aql \
  -X POST -H "Content-Type: text/plain" \
  -d 'items.find({"repo":"joern-pypi-local"}).include("name","path").limit(100)'
```

It also resolves through pip's actual protocol, which is worth showing side by
side with the AQL result to prove it's a real, installable package and not
just a file sitting in storage:

```bash
jf api "/artifactory/api/pypi/joern-pypi-local/simple/joern-demo-pkg/"
```

---

## 2. Package version lookup and metadata retrieval

**Say/type:**
> "What versions of `<PACKAGE>` do we have, and where are they stored?"

**Cut-and-paste verify** (OneModel GraphQL — package-centric, cross-repo):

```bash
QUERY='{ storedPackages { getPackage(name: "<PACKAGE>", type: "<npm|docker|maven|pypi|...>") { name type description versionsConnection(first: 10) { edges { node { version locationsConnection(first: 5) { edges { node { repositoryKey leadArtifactPath } } } } } } } } }'
jq -n --arg q "$QUERY" '{query:$q}' > /tmp/onemodel-payload.json
jf api /onemodel/api/v1/graphql -X POST -H "Content-Type: application/json" \
  --input /tmp/onemodel-payload.json | jq .
```

**Verified example** (`nodejs-demoapp` npm package, version 4.9.9, stored in
`joern-npm-local` at `nodejs-demoapp/-/nodejs-demoapp-4.9.9.tgz`) — same query,
already confirmed working against the test instance.

**Verified PyPI example** — `joern-demo-pkg` version 0.1.0, stored in
`joern-pypi-local` at `joern-demo-pkg/joern_demo_pkg-0.1.0.tar.gz`, same query
with `type: "pypi"`. Good scenario 2 pairing: run this right after the
scenario 1 PyPI discovery query to go from "what's in the repo" to "here's the
exact version and where it physically lives" in one follow-up question.

---

## 3. Build information, build history, and artifact traceability

**Say/type:**
> "What builds do we have for `<PACKAGE/PROJECT>`, and what went into the
> latest run?"

**Cut-and-paste verify** — list build names (paginated AQL, not the raw
`/api/build` endpoint which times out on large instances):

```bash
jf api /artifactory/api/search/aql \
  -X POST -H "Content-Type: text/plain" \
  -d 'builds.find().include("name","number","repo","created").sort({"$desc":["created"]}).limit(100)'
```

Then pull one run's full detail (always include `?project=`):

```bash
jf api "/artifactory/api/build/<build-name>/<build-number>?project=default"
```

**Verified example** — build `joern-demo-npm` #4 exists and its modules trace
straight from source to the shipped Docker image:

```bash
jf api "/artifactory/api/build/joern-demo-npm/4?project=default" \
  | jq '.buildInfo | {name, number, started, modules: [.modules[]?.id]}'
# → modules: ["nodejs-demoapp:4.9.9", "joern-demo-npm", "myapp-image:4"]
```

This is a strong traceability story: one build ties the npm package version to
the exact Docker image tag it was baked into.

---

## 4. Vulnerability and Xray-related queries

**Say/type:**
> "What's the security status of the Docker images in `<DOCKER-REPO>`?
> Break it down by severity and show me the critical CVEs."

**Cut-and-paste verify** — find manifests, then get the security summary:

```bash
# discover manifest paths
jf api /artifactory/api/search/aql \
  -X POST -H "Content-Type: text/plain" \
  -d 'items.find({"repo":"<DOCKER-REPO>","name":"manifest.json","path":{"$nmatch":"*_uploads*"}}).include("repo","path","name")'

# security summary for a specific tag
jf api /xray/api/v2/summary/artifact \
  -X POST -H "Content-Type: application/json" \
  -d '{"paths": ["default/<DOCKER-REPO>/<image>/<tag>/manifest.json"]}'
```

**Verified example** (already run live during prep) —
`joern-docker-local`, image `myapp-image`, tags 2–4: 56 issues each (4
Critical, 29 High, 17 Medium, 6 Low), including `CVE-2023-26136` (tough-cookie,
CVSS 9.8) and `CVE-2023-29827` (ejs, CVSS 9.8, no fix yet).

Optional follow-up to show Advanced Security depth:

```bash
jf api "/xray/api/v1/secrets/results?repo=<DOCKER-REPO>&path=<image>/<tag>/manifest.json&num_of_rows=50"
```

---

## 5. Repository structure, content exploration, and artifact location discovery

**Say/type:**
> "Show me the folder structure of `<REPO>`."
> "Where does `<artifact-name>` live?"

**Cut-and-paste verify** — repo listing, then deep content listing:

```bash
jf api /artifactory/api/repositories

jf api "/artifactory/api/storage/<REPO>?list&deep=1"
```

**Verified example** — `joern-docker-local` deep listing shows the manifest
and layer blobs per tag (`/myapp-image/2/manifest.json`,
`/myapp-image/2/sha256__...`, etc.).

---

## 6. Docker image and package lifecycle operations (where permissions allow)

**⚠️ Mutating — always confirm with the presenter/customer before running
live.** This is the one section where the MCP client should visibly pause for
confirmation; use that pause as a talking point about safe-by-default behavior.

**Say/type:**
> "Promote `<image>:<tag>` from `<staging-repo>` to `<prod-repo>`."
> "Delete `<image>:<old-tag>` from `<repo>`."

**Cut-and-paste verify:**

```bash
# promote (copy) a build's artifacts to a target repo
jf rt build-promote <build-name> <build-number> <target-repo>

# or copy/move a specific artifact
jf rt copy <source-repo>/<path> <target-repo>/<path>

# delete (irreversible — demo on a disposable tag only)
jf rt delete "<repo>/<image>/<tag>/*"
```

**Demo framing:** run this against a disposable tag created just for the demo,
not a real customer artifact. Narrate the confirmation step explicitly — it's
the strongest evidence that MCP-driven mutations aren't a blank check.

---

## 7. Package consumption and installation information (no manual doc digging)

**Say/type:**
> "How do I install `<PACKAGE>` from our Artifactory, and how many times has
> it been downloaded?"

**Cut-and-paste verify** — stats and location come from the same
`storedPackages` query as scenario 2, plus the `stats` field:

```bash
QUERY='{ storedPackages { getPackage(name: "<PACKAGE>", type: "<type>") { latestVersionName versionsConnection(first: 1) { edges { node { version stats { downloadCount } locationsConnection(first: 1) { edges { node { repositoryKey leadArtifactPath } } } } } } } } }'
jq -n --arg q "$QUERY" '{query:$q}' > /tmp/onemodel-payload.json
jf api /onemodel/api/v1/graphql -X POST -H "Content-Type: application/json" \
  --input /tmp/onemodel-payload.json | jq .
```

Combine the `repositoryKey` + `leadArtifactPath` from the response with the
package type's standard client config (`npm config set registry ...`, `pip
config set ...`, `docker pull <repo>/<image>:<tag>`) to hand the consumer a
ready-to-run install command without them ever opening the Artifactory UI.

**Verified example** — `myapp-image` in `joern-docker-local`: tag `2` has been
downloaded once (last pull 2026-07-28 07:16 UTC), tags `3` and `4` have never
been downloaded. Confirms `stats.downloadCount` and `lastDownloadedAt` both
resolve correctly at the version and location level.

**Verified PyPI example** — `joern-demo-pkg` 0.1.0 shows `downloadCount: 0`
(never installed yet, since it was just created for this prep). Combine with
the pip-install command derived from scenario 1/2's `repositoryKey` +
`leadArtifactPath`:
`pip install joern-demo-pkg --index-url https://<host>/artifactory/api/pypi/joern-pypi-local/simple/`
— a good live "download it now, watch the count go to 1" moment if there's
time in the demo.

---

## 8. Repository, project, and access management capabilities exposed through MCP

**Say/type:**
> "What users are configured on the platform?"
> "List the repositories and their types."
> "What members and roles exist in project `<project-key>`?"

**Cut-and-paste verify:**

```bash
# users (paginated via cursor)
jf api /access/api/v2/users

# repositories
jf api /artifactory/api/repositories

# project members/groups/roles
jf api "/access/api/v1/projects/<project-key>/users"
jf api "/access/api/v1/projects/<project-key>/groups"
jf api "/access/api/v1/projects/<project-key>/roles"
```

**Verified example** — this test instance has 3 users (`admin`, `anonymous`,
`msa`), all `internal` realm, all enabled. Good talking point: flag that
`anonymous` being enabled is worth a policy check, which naturally segues into
the permissions/access-management story.

---

## Discussion topics (not covered by a live command)

These are product/GTM questions the customer explicitly asked about. Answer
from JFrog's official MCP Server product guidance and deployment
documentation — don't improvise these live from what the demo happens to
show:

- Recommended MCP client(s) for evaluation
- Usage with VS Code (GitHub Copilot) and internal AI solutions
- Self-managed deployment model and operational considerations
- Recommended PoC scope and success criteria

## Appendix: reproducing the PyPI demo assets in another environment

If the customer's test instance has no PyPI content yet, this is exactly how
`joern-pypi-local` / `joern-pypi-remote` / `joern-demo-pkg` were created here,
end to end and independently verified:

```bash
# 1. Local PyPI repo
cat > /tmp/pypi-local-tpl.json << 'EOF'
{
  "key": "joern-pypi-local",
  "rclass": "local",
  "packageType": "pypi",
  "description": "Demo local PyPI repository (JFrog MCP evaluation)"
}
EOF
jf api /artifactory/api/repositories/joern-pypi-local -X PUT \
  -H "Content-Type: application/json" --input /tmp/pypi-local-tpl.json
echo '{"xrayIndex": true}' | jf api /artifactory/api/repositories/joern-pypi-local -X POST \
  -H "Content-Type: application/json" --input /dev/stdin

# 2. Remote PyPI repo, proxying pypi.org (matches the npm/docker remote pattern already in this instance)
cat > /tmp/pypi-remote-tpl.json << 'EOF'
{
  "key": "joern-pypi-remote",
  "rclass": "remote",
  "packageType": "pypi",
  "url": "https://pypi.org",
  "pyPIRegistryUrl": "https://pypi.org",
  "description": "Demo remote PyPI repository proxying pypi.org (JFrog MCP evaluation)"
}
EOF
jf rt repo-create /tmp/pypi-remote-tpl.json

# 3. A minimal real Python package (setuptools sdist — no network/build deps needed)
mkdir -p pypi-demo/joern_demo_pkg && cd pypi-demo
cat > setup.py << 'EOF'
from setuptools import setup, find_packages
setup(
    name="joern-demo-pkg",
    version="0.1.0",
    description="Demo PyPI package for JFrog MCP Server evaluation",
    packages=find_packages(),
    python_requires=">=3.7",
)
EOF
echo 'def hello(): return "hello from joern-demo-pkg"' > joern_demo_pkg/__init__.py
python3 setup.py sdist   # -> dist/joern_demo_pkg-0.1.0.tar.gz

# 4. Upload + index
jf rt upload "dist/joern_demo_pkg-0.1.0.tar.gz" \
  "joern-pypi-local/joern-demo-pkg/joern_demo_pkg-0.1.0.tar.gz"
jf api /artifactory/api/pypi/joern-pypi-local/reindex -X POST

# 5. Verify (metadata-layer indexing can take up to ~1 min after reindex)
jf api "/artifactory/api/pypi/joern-pypi-local/simple/joern-demo-pkg/"
```

Artifactory parses `pypi.name` / `pypi.version` / `pypi.summary` straight out
of the uploaded sdist's metadata — no manual property-setting needed. The
`storedPackages` GraphQL layer (used in scenarios 2 and 7) took about 40
seconds to pick up the new package after the reindex call in this environment;
budget for that delay if demoing the upload live rather than pre-seeding it.

## Pre-demo checklist

- [x] Confirm which test-environment repos map to each scenario — done for
      Docker (`joern-docker-local`), npm (`joern-npm-local`), and now PyPI
      (`joern-pypi-local` + `joern-pypi-remote`, created during prep — see
      appendix above)
- [x] Verify `stats.downloadCount` resolves for a real package (done —
      `myapp-image` in `joern-docker-local`, and `joern-demo-pkg` in
      `joern-pypi-local`)
- [ ] Confirm a build exists linking a package version to a deployed artifact,
      for scenario 3's traceability story
- [ ] Set up one disposable Docker tag for the scenario 6 mutation demo
- [ ] Confirm which MCP client the customer will actually use in the PoC, so
      the "say/type" prompts are demoed in that exact client
- [ ] Have a fallback terminal ready with `jf` CLI configured, in case a live
      MCP tool call needs the cut-and-paste verification path
