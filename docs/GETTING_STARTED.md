# Getting started — Cursor, extensions, scripts, and CloudHub

This guide is for developers opening this repo in **Cursor**. It complements [`agent-workflow.md`](./agent-workflow.md) (how the AI rules work) and the project’s [`API.md`](../API.md) / [`PROJECT_CONTEXT.md`](../PROJECT_CONTEXT.md) when those files exist.

---

## 1. Prerequisites (order matters)

1. **Cursor** — Primary IDE for this repo. AI assistance comes from Cursor plus the rule stack under [`.cursor/rules/`](../.cursor/rules/).
2. **Anypoint Code Builder (ACB)** — Install the [Anypoint Code Builder desktop app](https://developer.mulesoft.com/tutorials-and-howtos/getting-started/install-anypoint-code-builder/) from MuleSoft. ACB installs:
   - A **JDK 17** under `%USERPROFILE%\AnypointCodeBuilder\java\jdk-17*`
   - A **Mule Enterprise standalone** runtime under `%USERPROFILE%\AnypointCodeBuilder\runtime\mule-enterprise-standalone-*`  
   The PowerShell scripts expect these paths; they do not download the runtime for you.
3. **Apache Maven** — On your `PATH`, so `mvn` works in a terminal (used by `scripts/run-mule.ps1` to build the app).
4. **PowerShell** — Windows: built in. The tasks invoke `powershell -File ...`.
5. **Git** — To clone and branch the repo.

Optional but common: **JDK 17** elsewhere on the machine is fine for other tools; the run script still **pins** `JAVA_HOME` to ACB’s JDK 17 so Mule 4.8.x does not pick up JDK 21+.

---

## 2. Use the Visual Studio Code Marketplace in Cursor (for extensions)

Cursor’s default extension gallery may not list every VS Code–published extension (for example some MuleSoft-related packs). To search and install from the **same gallery as VS Code**:

### Option A — Command Palette (if available)

1. `Ctrl+Shift+P`
2. Run **`Extensions: Switch Marketplace`** (wording may vary slightly by Cursor version).
3. Choose **Visual Studio Code Marketplace** (or equivalent).
4. **Fully quit and restart Cursor**.

### Option B — `settings.json`

1. `Ctrl+Shift+P` → **Preferences: Open User Settings (JSON)**.
2. Add (merge with existing keys; do not duplicate top-level braces):

```json
{
  "extensionsGallery": {
    "serviceUrl": "https://marketplace.visualstudio.com/_apis/public/gallery",
    "itemUrl": "https://marketplace.visualstudio.com/items"
  }
}
```

3. Save, then **restart Cursor**.

**Note:** Switching galleries is a trade-off (updates, licensing, and publisher policies differ from Cursor’s default). If an extension still does not appear, use **Extensions: Install from VSIX...** after downloading the `.vsix` from the [Visual Studio Marketplace](https://marketplace.visualstudio.com/) in a browser.

---

## 3. Extensions to install (for this project and its rules)

The **Cursor rules** under `.cursor/rules/*.mdc` do not require a special extension — Cursor loads them automatically. For **editing, validating, and deploying** Mule apps the way the rules describe, install:

| Purpose | What to install | Notes |
|--------|------------------|--------|
| Mule 4 + DataWeave + MUnit + Exchange | **Anypoint Code Builder** (MuleSoft) — search Extensions for *Anypoint Code Builder* or *MuleSoft* and install the official pack | Provides `MuleSoft: Validate Project`, `MuleSoft: Add Dependency`, MUnit run actions, and **manual CloudHub deploy** entry points. |
| XML editing | Built-in or **XML** (e.g. Red Hat or similar) | Helps with flow XML and MUnit XML. |

After installing, run **`Developer: Reload Window`** if commands or completions look stale.

**Debug adapter:** In **Cursor**, the Mule `type: mule` debugger is **not** supported. Local run is via **Tasks** and `scripts/run-mule.ps1` (see below). **VS Code + ACB** is the path if you need F5 Mule debugging.

---

## 4. Open the project and secrets

1. **File → Open Folder** → select the repo root.
2. Copy **`.env.example`** to **`.env`** (if present) and fill in real values. **Never commit `.env`.**
3. Connector placeholders in Mule (e.g. `${sfdc.username}`) must match **JVM system properties** passed at startup — the run script maps `SFDC_*` from `.env` to `-M-D` args. See [`agent-workflow.md`](./agent-workflow.md) § Local-Dev Secrets Bootstrap.

---

## 5. How the helper scripts work (and how to change them)

All scripts live in [`scripts/`](../scripts/) and are wired from [`.vscode/tasks.json`](../.vscode/tasks.json).

### `scripts/run-mule.ps1` — task **Mule: Run (Cursor)**

1. Loads **`.env`** into the current process.
2. Sets **`JAVA_HOME`** to the newest **`jdk-17*`** under `%USERPROFILE%\AnypointCodeBuilder\java`.
3. Finds the newest **`mule-enterprise-standalone-*`** under `%USERPROFILE%\AnypointCodeBuilder\runtime`.
4. Runs **`mvn clean package -DskipTests`** from the repo root.
5. Clears the shared runtime **`apps/`** folder (so only this workspace’s app runs), then copies the built **`*-mule-application.jar`** into **`apps/`**.
6. Starts **`mule.bat console`** with **`-M-Dsfdc.username=...`** (and password/token) so Mule resolves `${sfdc.*}` — it does **not** rely on `MULE_OPTS` (Mule overwrites that).

**Changing it:** Edit the script if you add new secrets (append to `.env`, `.env.example`, and the `$muleArgs` array with matching `-M-Dyour.prop=$env:YOUR_ENV_VAR`). If your app name or JAR pattern differs, adjust the `Get-ChildItem` filter for the jar.

### `scripts/stop-mule.ps1` — task **Mule: Stop**

Stops Mule-related **wrapper** and **java** processes. Useful when the console task is stuck.

### `scripts/test-sfdc-login.ps1` — task **Salesforce: Test login (.env)**

SOAP login using values from `.env` and the Salesforce URL from project config — verifies credentials **outside** Mule.

### `scripts/smoke-test.ps1` — task **Mule: Smoke test**

HTTP checks aligned with **`API.md`**. Regenerate or edit when endpoints change (per project rules).

**Changing tasks:** In **`.vscode/tasks.json`**, each task’s `args` points at a script. You can duplicate a task block to add a new script, or change `label` / `group` for keybindings.

---

## 6. Run Mule from Cursor (tasks)

1. `Ctrl+Shift+P` → **Tasks: Run Task**
2. Choose **Mule: Run (Cursor)** (this is also the **default build** task — **`Ctrl+Shift+B`** runs it).
3. Wait until the log shows the app **DEPLOYED** (often ~60–90 seconds).
4. Stop with task **Mule: Stop** or **Ctrl+C** in the task terminal.
5. Optional: **Mule: Tail log** follows `%USERPROFILE%\AnypointCodeBuilder\runtime\...\logs\mule_ee.log`.

---

## 7. Deploy to CloudHub (manual, in Anypoint Code Builder)

This repo’s rules intentionally **do not** automate deployment. You deploy yourself:

1. Use **Anypoint Code Builder** features (Command Palette or the Mule / deployment UI your version exposes).
2. Run the action that publishes the application to **CloudHub** — for example commands named like **Deploy to CloudHub** / **Deploy application to CloudHub** (exact label depends on ACB version).
3. In **Anypoint Platform → Runtime Manager**, set **application properties** for every `${...}` the app expects (passwords as **secured**). Do **not** rely on `.env` in CloudHub.

For local-only runs, **Tasks + `run-mule.ps1`** are enough; CloudHub is for shared environments.

---

## 8. Where to read next

| Doc | Content |
|-----|--------|
| [`agent-workflow.md`](./agent-workflow.md) | Rule stack, Never-Guess policy, self-test gate, secrets |
| [`README.md`](./README.md) | Doc index for this folder |
| [`.cursor/rules/mulesoft-main.mdc`](../.cursor/rules/mulesoft-main.mdc) | Canonical delivery phases and IDE notes |
