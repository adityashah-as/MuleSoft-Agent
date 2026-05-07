# Project Documentation


> This folder explains the *machinery around the code*: how the AI agent is configured, and what every helper PowerShell script under `scripts/` actually does.
>
> For the **API surface** itself (endpoints, request/response shapes, demo calls) see [`../API.md`](../API.md).
> For the **project state** (runtime versions, env vars, decisions log) see [`../PROJECT_CONTEXT.md`](../PROJECT_CONTEXT.md).

---

## Index

### First-time setup

| Doc | Purpose |
|---|---|
| [**`GETTING_STARTED.md`**](./GETTING_STARTED.md) | **Start here in Cursor:** prerequisites (Cursor → ACB → Maven), switching the extension marketplace to the VS Code gallery, which extensions to install, how `scripts/*.ps1` work and how to change them, running **Tasks**, and **manual CloudHub** deploy via Anypoint Code Builder. |

### Agent

| Doc | Purpose |
|---|---|
| [`agent-workflow.md`](./agent-workflow.md) | How the Cursor AI agent works on this project — which rules apply, in what order, the Never-Guess policy, the self-test gates, and the end-of-session checklist the agent always shows. |

### Helper Scripts (`scripts/`)

All scripts live at `<project-root>/scripts/` and are wired into `.vscode/tasks.json` so they can be launched with one click via **Ctrl+Shift+P → Tasks: Run Task**. Step-by-step behavior and customization are in [**`GETTING_STARTED.md` § 5–6**](./GETTING_STARTED.md#5-how-the-helper-scripts-work-and-how-to-change-them).

| Script | Task label |
|---|---|
| `scripts/run-mule.ps1` | **Mule: Run (Cursor)** |
| `scripts/stop-mule.ps1` | **Mule: Stop** |
| `scripts/test-sfdc-login.ps1` | **Salesforce: Test login (.env)** |
| `scripts/smoke-test.ps1` | **Mule: Smoke test** |

> **`smoke-test.ps1`** is maintained against `API.md` where the project defines HTTP APIs. See [`../API.md`](../API.md) for the contract it tests.

---

## Conventions used across the docs

- **Code references** like `scripts/run-mule.ps1:117-122` point to a file at a specific line range.
- **Task labels** in **bold** are the exact labels in `.vscode/tasks.json`.
- **Env vars** are written in `SCREAMING_SNAKE_CASE` (e.g. `SFDC_USERNAME`).
- **Mule property placeholders** (resolved by the runtime) are written in `${dotted.name}` (e.g. `${sfdc.username}`).
- All shell commands are PowerShell unless explicitly tagged otherwise.
