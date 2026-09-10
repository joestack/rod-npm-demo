# Frogbot V3 setup — manual steps required on the JFrog Platform / GitHub

Checked live against the platform and GitHub on 2026-09-10. Two of the three
original concerns turned out to be different from what they looked like at
first — corrected below, with what was actually verified.

## 1. ⚠️ OIDC Identity Mapping — needs a decision, not just a value swap

Checked `GET /access/api/v1/oidc/joestack/identity_mappings` directly. Two
things came back that change the picture:

**a) Authentication for this repo already works today**, via a mapping named
`joestack` (priority 1) whose claims are already exactly
`{"repository": "joestack/rod-npm-demo"}`, granting
`applied-permissions/admin` scope. Since mapping evaluation goes by priority
and stops at the first match, this mapping — not `frogbot-oidc-mapping` —
is what will actually authenticate the two workflows as written. You don't
strictly need to change anything for the workflows to run.

**b) `frogbot-oidc-mapping` (priority 3) is malformed, not just wrong-valued.**
Its `claims` field isn't a flat object — it contains an entire duplicate
mapping definition nested inside it:

```json
{
  "name": "frogbot-oidc-mapping",
  "claims": {
    "name": "frogbot-oidc-mapping",
    "claims": { "repository": "joestack/frogbot-demo" },
    "priority": "3",
    "token_spec": { "username": "frogbot-svc", "scope": "applied-permissions/admin", ... }
  },
  "priority": 3
}
```

The repository constraint that's supposed to gate this mapping is two levels
deep (`claims.claims.repository`) instead of at the top level
(`claims.repository`). Editing just the string value to
`joestack/rod-npm-demo` won't fix it — the whole `claims` object needs to be
flattened to `{"repository": "joestack/rod-npm-demo"}`, dropping the nested
duplicate `name`/`priority`/`token_spec`.

**And even flattened, it still won't take effect for this repo**, because
mapping `joestack` (priority 1) already unconditionally matches
`joestack/rod-npm-demo` and is evaluated first. Fixing `frogbot-oidc-mapping`
alone changes nothing here unless one of these also happens:
- `frogbot-oidc-mapping` is reprioritized ahead of `joestack` (but then it
  would apply to *every* workflow in this repo, not just Frogbot's), or
- its claim is narrowed to something only Frogbot's workflows produce (e.g.
  matching on the `job_workflow_ref` claim against
  `joestack/rod-npm-demo/.github/workflows/frogbot-scan-*.yml`), so it wins on
  specificity for those runs while `joestack` still handles everything else.

**Decision for you:** do nothing and let Frogbot run under the existing
broad admin-scoped `joestack` mapping (works today, but Frogbot ends up with
more privilege than the dedicated `frogbot-svc` service user was presumably
meant to have) — or invest in properly scoping `frogbot-oidc-mapping` per the
above so Frogbot runs least-privilege. Path either way:
**JFrog Platform Administration → General → Manage Integrations → OpenID
Connect → `joestack` → Identity Mappings**.

## 2. ✅ Scanner enablement — already correct, nothing to configure

Checked live via `POST /xray/api/v1/xsc/profile_repos` with this repo's clone
URL — the same call Frogbot itself makes at scan time. No repo-specific
Config Profile exists, so Frogbot resolves to the platform's
`System_Default_Profile`, which already has:

| Scanner | Field | Value |
|---|---|---|
| SCA | `enable_sca_scan` | `true` |
| Snippet Detection | `enable_snippet_detection` | `false` ← matches "add later" |
| SAST | `enable_sast_scan` | `true` |
| Secrets | `enable_secrets_scan` | `true` |
| IaC | `enable_iac_scan` | `true` |
| Contextual Analysis | `enable_ca_scan` | `true` |

This already matches the desired state exactly. No Config Profile needs to
be created for this repo. (Correction from an earlier version of this doc,
which assumed — incorrectly — that scanners would be off by default without
one.)

## 3. ✅ GitHub Environment `frogbot` — created

Created via `gh api --method PUT repos/joestack/rod-npm-demo/environments/frogbot`.

**⚠️ One thing left:** it was created with **no required reviewers**
(`protection_rules: []`), so right now it provides no actual approval gate —
any `pull_request_target` run will proceed immediately. If the point was to
have a human approve PR scans before they run (the reason this environment
exists in Frogbot's own workflow pattern), add yourself or a team as a
required reviewer: **Settings → Environments → `frogbot` → required
reviewers**. I didn't pick a reviewer myself since that's your call to make,
not mine.

## 4. ✅ Target `frogbot` repository — created

Created: Generic Local, `packageType: generic`, Xray indexing enabled.
Verified via repository lookup.

**⚠️ One thing left:** the OIDC-mapped service user (`frogbot-svc`, per the
`frogbot-oidc-mapping` identity mapping — see item 1) still needs **Deploy**
permission on this repo. Repo creation doesn't grant permissions by itself.
Add it via **JFrog Platform Administration → Repositories → Permissions**
(or a Permission Target scoped to the `frogbot` repo with Deploy for
`frogbot-svc` / whichever identity ends up handling Frogbot's OIDC auth,
per the item 1 decision).

## Xray version — confirmed fine

This platform runs Xray 3.150.x, above both the general Frogbot V3 minimum
(3.143.6) and the Config Profile lookup's internal minimum (3.117.0).
