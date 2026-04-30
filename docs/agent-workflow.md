# Agent Workflow — How the Cursor AI Agent Works on This Project

This project is a **MuleSoft 4 + Anypoint Code Builder** codebase, but it is also an **AI-assisted** codebase. The Cursor agent that helps you edit it is configured by a stack of rule files under `.cursor/rules/`. Those rules turn a generic LLM into a Mule-specialist that hand-writes XML, DataWeave, MUnit, and PowerShell with the same conventions every time.

This doc explains:

1. The two-file source of truth the agent reads first
2. The 10 rule files and what each one governs
3. The Never-Guess policy — what the agent does when it lacks information
4. The Self-Test Gate — what the agent does *before* declaring work done
5. The Local-Dev Secrets Bootstrap — what the agent auto-creates on first credential need
6. Mode selection and tool conventions
7. The end-of-session checklist the agent always shows

If you ever want to understand "why did the agent just do X?" — the answer is in one of the files referenced below.

---

## 1. The Two Living Files — read FIRST, every session

| File | Purpose | Who owns it |
|---|---|---|
| [`PROJECT_CONTEXT.md`](../PROJECT_CONTEXT.md) | Project **state**: runtime versions, connector inventory, env vars, environments, decisions log | Agent (writes after every change), human (reviews) |
| [`API.md`](../API.md) | Human-readable **API reference**: every endpoint with demo request/response, errors, headers | Agent (kept in lockstep with flows + spec) |

Before any code work, the agent reads `PROJECT_CONTEXT.md`. If it doesn't exist, the agent runs the **Init Workflow** from `mule-init-context.mdc` (asks a batched set of questions, then writes the file). If `API.md` is missing on a project that has at least one HTTP endpoint, it scaffolds that too.

These two files are the project's **memory** — if they drift from reality, every future chat is wrong.

---

## 2. The Rule Stack (`.cursor/rules/`)

Cursor loads rules from `.cursor/rules/*.mdc`. Some are `alwaysApply: true` (loaded for every prompt); others are `alwaysApply: false` and only attach when their `globs:` match the files in scope. Order of relevance:

| # | Rule file | When it loads | What it governs |
|---|---|---|---|
| 1 | `mulesoft-main.mdc` | Always | The "table of contents" for the rule stack. Project-wide naming conventions, Mule version policy, the secrets policy, the **local testing workflow** (Cursor task vs ACB F5), and the rule index that points to the focused rules below. |
| 2 | `mule-init-context.mdc` | Always | The Init Workflow, the **Never-Guess Policy**, the `PROJECT_CONTEXT.md` template, the `.env` / `launch.json` bootstrap, the deployment-secrets handoff table (CloudHub / RTF / on-prem), and the end-of-session checklist. |
| 3 | `mule-api-docs.mdc` | Always | The `API.md` structure and the cross-file consistency rules: every endpoint change must update RAML *and* flow XML *and* MUnit *and* `API.md` *and* `PROJECT_CONTEXT.md` § 4 in the same response. |
| 4 | `mule-project-scaffold.mdc` | When touching `pom.xml`, `mule-artifact.json`, `config.yaml`, or `global-configs.xml` | New-project skeleton, connector dependency GAVs, the **Self-Test Wiring** (which scaffolds `scripts/smoke-test.ps1` + the `Mule: Smoke test` task). |
| 5 | `mule-flow-generation.mdc` | When touching `src/main/mule/**/*.xml` | Flow / sub-flow naming, the required XML root namespaces, HTTP listener response config, the **error-handler pattern** (one `<on-error-propagate>` per known error type plus a catch-all `ANY`), the user-friendly error envelope (`{ code, message }`), CDATA gotchas, and the **Self-Test Gate** (the agent's mandatory lint + smoke check before declaring work done). |
| 6 | `mule-dataweave.mdc` | When touching `*.dwl` or `src/main/mule/**/*.xml` | DataWeave 2.0 header rules (one `---`, `output` first), null-safety with `default`, identifier rules (`_` is **not** a wildcard), the cross-language anti-pattern table (no `arr.length`, use `sizeOf(arr)`), the **forbidden-substring blocklist** (`encoding:` as a reader prop, `payload[0]` for SF, `${env.X}` in YAML, `]]]>` at end of CDATA, etc.), and the pre-deploy self-check. |
| 7 | `mule-testing-munit.mdc` | When touching `src/test/munit/**/*.xml` | MUnit file naming, minimum coverage per flow (happy path + error path + edge case), how to mock connectors, the assertion API, and the two-layer test gate (MUnit = unit/contract; smoke test = end-to-end). |
| 8 | `mule-database.mdc` | When touching DB connector usage | JDBC driver coordinates per database, `<db:config>` per-vendor connection elements, parameterized SQL with `:name` placeholders, and the standard DB error mapping (`DB:CONNECTIVITY` → 503, `DB:BAD_SQL_SYNTAX` → 500). |
| 9 | `mule-salesforce.mdc` | When touching Salesforce connector usage | Salesforce auth flows, the **CRITICAL login-endpoint table** (Production vs Sandbox vs Developer Edition vs My Domain — wrong endpoint always returns `INVALID_LOGIN`), the **actual response shape** of `sfdc:create` / `sfdc:update` / `sfdc:upsert` (read `payload.items[0]`, NEVER `payload[0]`), the user-friendly SF error pattern (sub-flow captures `vars.sfErrorCode` / `vars.sfErrorMessage` → outer handler maps SF `statusCode` → HTTP status), and the canonical SF-status-code → HTTP-status table. |
| 10 | `mule-api-spec.mdc` | When touching `src/main/resources/api/**` | RAML 1.0 vs OAS 3.0 conventions, required-per-resource fields (request body type with example, all realistic error responses), `ErrorResponse` shape, and version-segment consistency between RAML `baseUri`, `<http:listener>` `path`, and `config.yaml` `http.basePath`. |

### How they compose

Every prompt loads rules 1–3 (the always-apply set). Rules 4–10 attach when you're working in their globs. So if you ask "add a new POST endpoint that hits Salesforce", the loaded rule set is:

1, 2, 3 (always), then 5 (flow XML), 6 (DW inside the flow), 7 (you'll add a MUnit case), 9 (SF connector). Rules 4, 8, 10 don't load unless you also touch scaffolding / DB / API spec — but the agent will still *consult* `mule-api-spec.mdc` for the spec change because rule 3 (`mule-api-docs.mdc`) tells it that endpoint changes must update the RAML.

---

## 3. The Never-Guess Policy

If a value, name, host, port, credential location, environment URL, SObject name, table name, or any other project-specific detail is **not in `PROJECT_CONTEXT.md`** and **not directly given by the user in this session**, the agent MUST:

1. Stop. Don't generate code, XML, configs, or commands using a guessed value.
2. Use the `AskQuestion` tool (or plain text) to ask the user for the missing detail(s) — batched.
3. Once answered, **immediately update `PROJECT_CONTEXT.md`** with the new info (without secrets).
4. Then resume the task.

The agent never substitutes placeholders like `your-host`, `TODO`, `example.com`, `XXXX` and calls the work done.

---

## 4. The Self-Test Gate — what runs *before* "done"

`mule-flow-generation.mdc` § Self-Test Gate makes the agent run these gates, in order, before reporting any flow / DW work as finished:

1. **Lint** — `ReadLints` on every edited XML / DW file. Any `[ERROR]` is a deploy-blocker. Fix before continuing.
2. **Mule reachable check** — confirm the runtime is up (`Get-NetTCPConnection -LocalPort 8081`). If down, ask you to start it via task **Mule: Run (Cursor)** before proceeding.
3. **Smoke test** — run `scripts/smoke-test.ps1` (or task **Mule: Smoke test**). The script hits every endpoint declared in `API.md`, asserts on HTTP status + response shape + known sample values from the bundled fixtures, and exits 0 / 1.
4. **Update fixtures if surface changed** — if the change added/removed an endpoint, changed a field name, changed a status code, or changed an error code, the agent updates `scripts/smoke-test.ps1` in the **same response** so the new gate is meaningful.

The gate is allowed to be skipped only when the change is purely documentation (`API.md`, `PROJECT_CONTEXT.md`, `*.mdc`, README), or purely a test fixture under `src/test/resources/` that no flow loads, or purely `pom.xml` / `mule-artifact.json` with no XML/DW touched (run `mvn validate` instead).

### What the gate catches

The lint gate catches **parse-time** bugs. The smoke gate catches **runtime** bugs:

- `readUrl` MIME-type bugs (parse fine, fail at first request)
- Wrong status codes (200 returned where 404 expected)
- Wrong error envelope shape (`code` field missing, `message` empty)
- Wrong field names in the response (`Price` vs `price`)
- Wrong field types (numeric returned as quoted string `"193.52"`)
- Stale `vars.*` references that compile but resolve to null at runtime

Both classes are in scope; both gates are required.

---

## 5. Local-Dev Secrets Bootstrap

When a connector that needs credentials is added (Salesforce, Database, HTTP outbound with auth, FTP, JMS, …), the agent **automatically** creates the full local-dev secrets bootstrap. Four coordinated changes, in this order:

1. **`.env`** (gitignored) — real values, one var per line.
2. **`.env.example`** (committed) — same names, empty values, comments documenting where to obtain each secret.
3. **`.vscode/launch.json`** — passes env vars as JVM system properties via `-M-D<mule.prop.name>=${env:<ENV_VAR_NAME>}` args.
4. **`.gitignore`** — append `.env`, `.env.local`, `.env.*.local` (never ignore `.env.example` or `.vscode/launch.json`).

Plus coordinated XML and YAML changes:

- **`global-configs.xml`** uses plain placeholders matching the `-M-D` keys (`${sfdc.username}`, **NOT** `${env.SFDC_USERNAME}`)
- **`config.yaml`** holds **only non-secret defaults** (URLs, hosts, ports, basePath); never credential entries
- **Launch args mapping**: every secret in `.env` has a matching `-M-D…=${env:…}` line in **both** launch configs

> **Why this matters**: Mule 4's `<configuration-properties>` resolver does **NOT** auto-translate `${env.SFDC_USERNAME}` into "read OS env var SFDC_USERNAME". It treats `env.SFDC_USERNAME` as a literal property name. If no such property is loaded, deploy fails with `PropertyNotFoundException: Couldn't find configuration property value for key ${env.SFDC_USERNAME:}`. The trailing `:` in that error is Mule's default-value separator — confirms it's a placeholder-resolution failure, not a connection issue. The fix is always to inject the value as a JVM system property at startup (`-M-D<prop>=<value>`) and reference `${<prop>}`. That's what `scripts/run-mule.ps1` does — see [`scripts/run-mule.md`](./scripts/run-mule.md).

### Mule Standalone Runtime gotcha — `MULE_OPTS` is overwritten

When running the standalone runtime via `mule.bat console` (the Cursor task path), do **NOT** try to inject system properties through `$env:MULE_OPTS`. Line ~113 of `mule.bat` unconditionally overwrites the caller's `MULE_OPTS` with internal wrapper-configuration values. Anything you set before invoking `mule.bat` is lost.

The correct pattern is to pass system properties as **positional command-line args** using the `-M-D<prop>=<value>` syntax AFTER the command label. `launcher.bat` runs `mule-wrapper-additional-parameters-parser.jar` which converts `-M-D<key>=<value>` args into JVM `-D` system properties for the spawned Mule JVM. This is exactly what `scripts/run-mule.ps1` does — every new secret added MUST land in three places: `.env`, `.env.example`, AND the `-M-D` arg list in `scripts/run-mule.ps1`.

### Deployment Secrets Handoff — `.env` is LOCAL-ONLY

`.env` is a developer-laptop convenience. It is **never** part of any deployment artifact and **must not** be relied on in any non-local environment. When asked "will this work when I deploy it?" the agent always answers YES — secrets MUST be set on the deployment target — and shows the appropriate row from this table:

| Target | Where to set `${sfdc.username}` / `${sfdc.password}` etc. |
|---|---|
| **Developer laptop (Cursor)** | `.env` → `scripts/run-mule.ps1` → `-M-D` args. Already wired. |
| **Another developer's laptop** | They copy `.env.example` → `.env`, fill values, run task **Mule: Run (Cursor)**. |
| **On-prem standalone Mule runtime** | Either edit `<MULE_HOME>/conf/wrapper.conf` and add `wrapper.java.additional.<n>=-Dsfdc.username=...` per property (restart). Or launch with `mule.bat console -M-Dsfdc.username=... -M-Dsfdc.password=... -M-Dsfdc.token=...`. |
| **CloudHub 1.0 / 2.0** | Anypoint Platform → Runtime Manager → app → **Properties** tab → add one row per `${name}`. Mark password/token rows as **secured** (eye icon). |
| **Runtime Fabric** | Either Properties in Runtime Manager, OR a Kubernetes Secret mounted via `<secure-properties:config>`. Document the choice in `PROJECT_CONTEXT.md`. |
| **Production (any target)** | Strongly prefer encrypted `secure-properties.yaml` (committed) + a single `runtime.encryption.key` injected at deploy time. |

The agent never suggests copying `.env` into the deployment, baking it into the JAR, or committing it.

---

## 6. Mode Selection & Tool Conventions

The agent operates in one of several **modes**:

| Mode | When | What changes |
|---|---|---|
| **Agent** (default) | Clear, well-scoped implementation work | Full tool access — can edit files, run shell commands, install deps |
| **Plan** | Large or ambiguous task with meaningful trade-offs | Read-only collaborative mode for designing approaches before coding |
| **Debug** | Investigating a bug with runtime evidence | Systematic troubleshooting workflow |
| **Ask** | Pure exploration / Q&A | Read-only — no file edits |

The agent switches modes proactively when the goal changes; you can also force a switch.

### Tool conventions on this project

- **File ops** use specialized tools (`Read`, `Edit`, `Write`, `Glob`, `Grep`). Shell is reserved for actual system commands (git, mvn, npm, docker).
- **Searches** prefer `Grep` (built on ripgrep) for known strings/symbols and `Glob` for file-name patterns. `SemanticSearch` is used only for "how / where / what" questions about unfamiliar code.
- **Background commands** are spawned with `block_until_ms: 0`. The agent doesn't poll reflexively; it relies on completion notifications.
- **Lints** are run via `ReadLints` after substantive edits — only on files the agent just touched.

---

## 7. End-of-Session Checklist

When a development task is complete (feature shipped, code generated, tests written), the agent **always** ends its response with a copy-pasteable checklist that you tick off before running locally. Tailored to the work done — but at minimum it includes:

```
## Before you run locally — please complete:

- [ ] Open `.env` and replace ALL `replace-with-real-value` placeholders with real credentials:
  - SFDC_USERNAME
  - SFDC_PASSWORD
  - SFDC_SECURITY_TOKEN
  (and any other secrets added this session)
- [ ] Confirm `.env` is gitignored (run: `git check-ignore .env` — should print `.env`)
- [ ] In Anypoint Code Builder: open `global-configs.xml` → click each connector config → Test Connection
- [ ] Run task **Mule: Run (Cursor)** (or hit F5 if you're in VS Code + ACB)
- [ ] Wait for `DEPLOYED` in the log (~60–90s)
- [ ] Smoke-test endpoints with `Invoke-RestMethod` (commands inline below)

## Smoke-test commands
(...PowerShell `Invoke-RestMethod` for each new endpoint...)
```

If the session didn't add any new secrets and `.env` already has real values, the placeholder-replacement step is dropped — but the connection-test + smoke-test items remain.

---

## 8. The IDE Distinction — Cursor vs ACB-in-VS-Code

The **same project** runs differently depending on which editor you opened it in:

| IDE | Recommended way to run | Why |
|---|---|---|
| **Cursor** | `.vscode/tasks.json` task **Mule: Run (Cursor)** which calls `scripts/run-mule.ps1` | The ACB Mule debug adapter (`type: mule`) is **not supported in Cursor** — F5 fails with "Configured debug type 'mule' is not supported" or JS errors like "split is not defined" |
| **VS Code + Anypoint Code Builder** | F5 → debug config in `launch.json` (`type: mule`) | Works because the ACB extension installs the debug adapter |

When the project is opened in Cursor, the agent always directs you to the task — never tells you to "press F5" or "use ACB Run" without first confirming which IDE you're in.

This is also why the helper script (`run-mule.ps1`) exists at all: it replicates ACB's launch behavior using only PowerShell + `mule.bat`, so Cursor users aren't second-class citizens. See [`scripts/run-mule.md`](./scripts/run-mule.md) for the full breakdown.

---

## 9. Meta-Rule — improving the rules

When the agent encounters a project detail that doesn't fit any template section in the rules, OR a recurring question pattern that should be standardized, it:

1. Adds the detail to `PROJECT_CONTEXT.md` (project state)
2. Proposes a small addition to the relevant rule file (`.cursor/rules/*.mdc`) so future projects benefit — shows the diff to the user and waits for approval before writing.

This is how the rule stack grows. The `Forbidden Patterns` table in `mule-dataweave.mdc` and the `CRITICAL Mule Property Resolution Gotcha` section in `mule-init-context.mdc` both started as one-off debugging sessions that the agent then folded back into the rules — so the next debugging session never repeats them.

---

## TL;DR

- **Two files** the agent reads first: `PROJECT_CONTEXT.md` (state) and `API.md` (API surface).
- **Ten rule files** in `.cursor/rules/` configure the agent — three load always, seven attach by file glob.
- **Never-Guess Policy** — missing info = ask; never substitute placeholders.
- **Self-Test Gate** — lint + reach check + smoke test before any flow/DW change is "done".
- **Local-Dev Secrets Bootstrap** — `.env` + `.env.example` + `launch.json` + `global-configs.xml` placeholders, all coordinated.
- **`.env` is LOCAL-ONLY** — never deployed; deployment targets get secrets via Runtime Manager / wrapper.conf / Kubernetes Secret.
- **Cursor uses `scripts/run-mule.ps1`** because the ACB debug adapter doesn't run in Cursor.
- **End-of-session checklist** is always shown so you can verify before running.
