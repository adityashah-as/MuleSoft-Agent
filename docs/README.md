# Project Documentation

> Internal docs for the **Product Price API** — a MuleSoft 4 project developed in Anypoint Code Builder / Cursor.
>
> This folder explains the *machinery around the code*: how the AI agent is configured, and what every helper PowerShell script under `scripts/` actually does.
>
> For the **API surface** itself (endpoints, request/response shapes, demo calls) see [`../API.md`](../API.md).
> For the **project state** (runtime versions, env vars, decisions log) see [`../PROJECT_CONTEXT.md`](../PROJECT_CONTEXT.md).

---

## Index

### Agent

| Doc | Purpose |
|---|---|
| [`agent-workflow.md`](./agent-workflow.md) | How the Cursor AI agent works on this project — which rules apply, in what order, the Never-Guess policy, the self-test gates, and the end-of-session checklist the agent always shows. |

### Helper Scripts (`scripts/`)

All scripts live at `<project-root>/scripts/` and are wired into `.vscode/tasks.json` so they can be launched with one click via **Ctrl+Shift+P → Tasks: Run Task**.

| Doc | Script | Task label |
|---|---|---|
| [`scripts/run-mule.md`](./scripts/run-mule.md) | `scripts/run-mule.ps1` | **Mule: Run (Cursor)** |
| [`scripts/stop-mule.md`](./scripts/stop-mule.md) | `scripts/stop-mule.ps1` | **Mule: Stop** |
| [`scripts/test-sfdc-login.md`](./scripts/test-sfdc-login.md) | `scripts/test-sfdc-login.ps1` | **Salesforce: Test login (.env)** |

> The project also ships `scripts/smoke-test.ps1` (task **Mule: Smoke test**) which is generated/maintained by the agent from `API.md`. It isn't documented here as a standalone script because it is a project-specific artifact, not generic tooling — its assertions live and breathe with the API surface. See [`../API.md`](../API.md) for the contract it tests.

---

## Conventions used across the docs

- **Code references** like `scripts/run-mule.ps1:117-122` point to a file at a specific line range.
- **Task labels** in **bold** are the exact labels in `.vscode/tasks.json`.
- **Env vars** are written in `SCREAMING_SNAKE_CASE` (e.g. `SFDC_USERNAME`).
- **Mule property placeholders** (resolved by the runtime) are written in `${dotted.name}` (e.g. `${sfdc.username}`).
- All shell commands are PowerShell unless explicitly tagged otherwise.
