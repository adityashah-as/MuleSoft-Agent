# `scripts/run-mule.ps1` — Local Mule Runner for Cursor

> **Task label**: `Mule: Run (Cursor)` (default build task — bound to `Ctrl+Shift+B`)
> **Source**: [`../../scripts/run-mule.ps1`](../../scripts/run-mule.ps1)
> **Companion script**: [`stop-mule.md`](./stop-mule.md)

---

## What it does (one line)

Builds the current Mule app with Maven, drops the resulting jar into the bundled standalone runtime under `~/AnypointCodeBuilder/runtime/mule-enterprise-standalone-*/apps/`, and starts the runtime in console mode with all `.env` secrets forwarded as JVM system properties — so you get the same `DEPLOYED` log you'd get from F5-in-ACB, without needing the ACB debug adapter (which doesn't load in Cursor).

---

## Why this script exists

Cursor doesn't ship the Anypoint Code Builder debug adapter. Trying to F5 a Mule project from Cursor fails with one of:

- `Configured debug type 'mule' is not supported`
- `split is not defined`

The official ACB launch config (`type: mule` in `launch.json`) is therefore unusable here. This script replicates ACB's launch behavior using only PowerShell + `mule.bat`, so a Cursor user can run the project with one click.

---

## When to use it

- **Always**, when you're in Cursor and want to run the app locally
- After **any** code change to the flow XML, DataWeave, or `pom.xml` — the script does a clean Maven build every time, so there's no stale-jar risk
- After editing `.env` — the script re-loads `.env` on each invocation, so credentials always reflect what's on disk
- Before invoking `scripts/smoke-test.ps1` (or the **Mule: Smoke test** task), since the smoke script needs the runtime up

If you're in **VS Code with the ACB extension installed**, prefer F5 → "Run Mule App" — the debug experience is richer (breakpoints in DW). Otherwise, this script.

---

## Pre-flight checklist (the script assumes these are true)

| Requirement | How to verify | If missing |
|---|---|---|
| Anypoint Code Builder installed (provides bundled JDK 17 + Mule runtime) | `Test-Path "$env:USERPROFILE\AnypointCodeBuilder"` returns `True` | Install ACB from the VS Code Marketplace; it provisions both directories on first launch |
| `~/AnypointCodeBuilder/java/jdk-17*` exists | `Get-ChildItem ~/AnypointCodeBuilder/java -Directory` shows a `jdk-17.*` folder | ACB hasn't pulled the JDK yet — open ACB once and let it bootstrap |
| `~/AnypointCodeBuilder/runtime/mule-enterprise-standalone-*` exists | `Get-ChildItem ~/AnypointCodeBuilder/runtime -Directory` shows a `mule-enterprise-standalone-*` folder | Same as above — ACB downloads the runtime on first run |
| `mvn` is on `PATH` | `mvn -v` succeeds | Install Maven 3.9+ and add to `PATH` |
| Port `8081` is free | `Get-NetTCPConnection -LocalPort 8081 -ErrorAction SilentlyContinue` returns nothing | Run task **Mule: Stop**, or kill the offender (`Stop-Process -Id <pid>`) |
| `.env` exists at project root with values for every secret in `.env.example` | `Test-Path .env` returns `True`; cross-check keys against `.env.example` | Copy `.env.example` → `.env` and fill in the values |

---

## What it does — step by step (with line refs)

The script runs in 6 numbered phases. Each one prints `==> ...` to the terminal so you can match the log to a phase.

### Phase 1 — Load `.env` into the current process (lines 24–48)

```24:48:scripts/run-mule.ps1
$envFile = Join-Path $projectRoot '.env'
if (Test-Path $envFile) {
  Write-Step "Loading $envFile"
  Get-Content $envFile | ForEach-Object {
    if ($_ -match '^\s*#') { return }
    if ($_ -match '^\s*$') { return }
    if ($_ -match '^\s*([^=]+?)\s*=\s*(.*?)\s*$') {
      $name = $matches[1].Trim()
      $value = $matches[2].Trim()
      Set-Item -Path "Env:$name" -Value $value
    }
  }
  ...
```

- Reads `.env` line by line, skipping comments (`#`) and blank lines
- Each `KEY=VALUE` becomes a process env var via `Set-Item Env:KEY`
- After loading, it sanity-checks Salesforce-related vars: if any of `SFDC_USERNAME` / `SFDC_PASSWORD` / `SFDC_SECURITY_TOKEN` is **declared but empty**, the script aborts. (If they aren't declared at all — i.e. this project doesn't use Salesforce — the loop is silent.)
- If `.env` is missing entirely, you get a `Write-Warning` and execution continues. Most projects need it; if your flows reference `${...}` properties (like `${sfdc.username}`), the runtime will then fail at deploy with `PropertyNotFoundException`.

### Phase 2a — Pin `JAVA_HOME` to ACB's bundled JDK 17 (lines 50–65)

```50:65:scripts/run-mule.ps1
$jdkBase = Join-Path $env:USERPROFILE 'AnypointCodeBuilder\java'
if (-not (Test-Path $jdkBase)) {
  Write-Error "ACB JDK folder not found at $jdkBase. Install Anypoint Code Builder runtime."
}
$jdk = Get-ChildItem -Directory $jdkBase |
  Where-Object Name -like 'jdk-17*' |
  Sort-Object Name -Descending |
  Select-Object -First 1
...
$env:JAVA_HOME = $jdk.FullName
$env:PATH = (Join-Path $jdk.FullName 'bin') + ';' + $env:PATH
```

- Mule Runtime 4.8.x supports **up to JDK 17 only**. If your machine's default `JAVA_HOME` is JDK 21+, the Maven build crashes with `Version 4.8.10 doesn't support JVM version 21.0.9`.
- To dodge that, the script picks the **latest `jdk-17*` folder under `~/AnypointCodeBuilder/java/`** and overrides `JAVA_HOME` + prepends `<jdk>/bin` to `PATH` for the lifetime of this PowerShell session. Your global `JAVA_HOME` is unchanged.

### Phase 2b — Discover the runtime (lines 67–79)

```67:79:scripts/run-mule.ps1
$runtimeBase = Join-Path $env:USERPROFILE 'AnypointCodeBuilder\runtime'
...
$runtime = Get-ChildItem -Directory $runtimeBase |
  Where-Object Name -like 'mule-enterprise-standalone-*' |
  Sort-Object Name -Descending |
  Select-Object -First 1
```

- Looks under `~/AnypointCodeBuilder/runtime/` for `mule-enterprise-standalone-*` and picks the **latest** by name (so a 4.8.10 install wins over a 4.8.9). If you need a specific version, archive newer ones out of that folder.

### Phase 3 — Build with Maven (lines 81–92)

```81:92:scripts/run-mule.ps1
Write-Step "mvn clean package -DskipTests"
& mvn clean package -DskipTests
if ($LASTEXITCODE -ne 0) { throw "Maven build failed (exit $LASTEXITCODE)" }

$jar = Get-ChildItem (Join-Path $projectRoot 'target') -Filter '*-mule-application.jar' |
  Sort-Object LastWriteTime -Descending |
  Select-Object -First 1
```

- Always a clean build (`-DskipTests` is on because MUnit needs the embedded runtime BOM and Anypoint Exchange creds that may not be configured locally — run tests via ACB's "Run MUnit Tests" or set `-DskipMunitTests=false` if your `~/.m2/settings.xml` resolves `com.mulesoft.mule.distributions`).
- Locates the freshly built jar in `target/` (the Mule Maven plugin produces `*-mule-application.jar`).

### Phase 4 — Deploy the jar to the runtime (lines 94–110)

```94:110:scripts/run-mule.ps1
$appsDir = Join-Path $runtime.FullName 'apps'
if (Test-Path $appsDir -PathType Leaf) {
  Write-Step "Removing stale '$appsDir' file (should be a directory)"
  Remove-Item $appsDir -Force
}
if (-not (Test-Path $appsDir)) {
  New-Item -ItemType Directory -Path $appsDir | Out-Null
}
$deployTarget = Join-Path $appsDir $jar.Name
Write-Step "Copying jar to $deployTarget"
Copy-Item $jar.FullName $deployTarget -Force
```

- A **fresh** standalone runtime ships **without** an `apps/` folder. PowerShell's `Copy-Item` to a non-existent destination creates a **file** at that path — which then poisons the runtime (next start: `NotDirectoryException`). Defensive: ensure `apps/` is a directory first, then copy with an explicit destination filename.

### Phase 5 — Build the system-property arg list (lines 112–123)

```112:123:scripts/run-mule.ps1
$muleArgs = @(
  'console',
  "-M-Dsfdc.username=$($env:SFDC_USERNAME)",
  "-M-Dsfdc.password=$($env:SFDC_PASSWORD)",
  "-M-Dsfdc.token=$($env:SFDC_SECURITY_TOKEN)"
)
```

> **The crucial bit.** `mule.bat` overwrites `$env:MULE_OPTS` internally (line ~113 of `mule.bat`), so any properties you set there are lost. The supported pattern is positional args using `-M-D<prop>=<value>`. `launcher.bat` runs `mule-wrapper-additional-parameters-parser.jar` which converts those into JVM `-D` system properties for the spawned Mule JVM. The matching `${sfdc.username}` placeholder in `global-configs.xml` then resolves correctly.

This is also why **adding a new connector secret requires three coordinated edits** — see [`agent-workflow.md`](../agent-workflow.md) § 5.

### Phase 6 — Run the runtime in console mode (lines 125–129)

```125:129:scripts/run-mule.ps1
$muleBat = Join-Path $runtime.FullName 'bin\mule.bat'
Write-Step "Starting Mule in console (Ctrl+C to stop)..."
Write-Host ""
& $muleBat @muleArgs
```

- `mule.bat console` runs the runtime in the foreground and streams logs to the task panel — same effect as ACB's launch.
- `Ctrl+C` in the task panel stops it cleanly. (If that hangs or you closed the terminal, run task **Mule: Stop** — see [`stop-mule.md`](./stop-mule.md).)

---

## How to run it

### Recommended — via the task

1. `Ctrl+Shift+P` → `Tasks: Run Task` → **Mule: Run (Cursor)**
2. (Or `Ctrl+Shift+B` since it's the default build task.)
3. Wait for `*** STATUS ***` block ending in `DEPLOYED` (~60–90s on a warm machine, longer cold)
4. Hit endpoints — see [`../../API.md`](../../API.md) for `Invoke-RestMethod` examples

### Direct invocation (debugging the script itself)

```powershell
pwsh ./scripts/run-mule.ps1
```

(Use `pwsh` if you're on PowerShell 7+; `powershell` for Windows PowerShell 5.1.)

---

## Reading the log — what success looks like

The runtime prints a lot. Three landmarks tell you it worked:

1. `INFO  ... Started app 'product-price-api-1.0.0-SNAPSHOT-mule-application'` — XML parsed, beans wired
2. A `*** STATUS ***` ASCII box listing each app and `DEPLOYED` next to it
3. `INFO  ... Listener 'HTTP_Listener' on http://0.0.0.0:8081 started` — confirms the port is bound

If you see `DEPLOYED` but the port log is missing, your `<http:listener-config>` didn't pick up `${http.host}` / `${http.port}` correctly — check `config.yaml`.

If you see `FAILED` instead of `DEPLOYED`, scroll **up** for the first stack trace. The most common deploy-time failures on this project:

| Log signature | Cause | Fix |
|---|---|---|
| `PropertyNotFoundException: Couldn't find configuration property value for key ${env.X:}` | Used `${env.X}` in YAML/XML expecting it to read OS env var | Switch to `${X}` (plain placeholder) and add `-M-DX=...` to the script's arg list |
| `Invalid input ']', expected ~, Function Call or selectors` at a `<![CDATA[` line | Stray `]` before `]]>` (looks like `]]]>`) | Remove the extra `]` |
| `Exception while reading '...' as 'application/dw'` | `readUrl(url)` called with no MIME type | Pass an explicit MIME type as the second arg (e.g. `"application/csv;charset=UTF-8"`) |
| `Option 'encoding' is not valid. Valid options are: streaming, separator, ...` | Used `encoding:` as a CSV/JSON/XML reader property | Drop `encoding` from the third-arg props; put charset in the MIME type instead |
| `INVALID_LOGIN: Invalid username, password, security token` (Salesforce) | Wrong login URL (sandbox vs prod), wrong token after a password reset, missing `.sandboxname` suffix on username | Run task **Salesforce: Test login (.env)** to isolate the credential issue from the Mule pipeline — see [`test-sfdc-login.md`](./test-sfdc-login.md) |

---

## Adding a new secret-bearing connector

When you add a connector that needs credentials (Salesforce, DB password, OAuth secret, FTP password…), four files change in lockstep:

1. **`.env`** — add the var with the real value
2. **`.env.example`** — add the var with empty value + comment
3. **`scripts/run-mule.ps1`** — append a new line in the `$muleArgs` array:
   ```powershell
   "-M-D<mule.placeholder>=$($env:<ENV_VAR>)"
   ```
4. **`global-configs.xml`** — reference the placeholder (`${<mule.placeholder>}`) in the connector config

If you skip #3, the runtime starts but the connector config sees an unresolved placeholder and deploy fails. The agent always does all four together — see [`agent-workflow.md`](../agent-workflow.md) § 5.

---

## Common failures of the script itself

| Symptom | Cause | Fix |
|---|---|---|
| `ACB JDK folder not found at C:\Users\...\AnypointCodeBuilder\java` | ACB not installed, or installed but never opened | Install ACB and launch it once so it bootstraps the JDK |
| `No jdk-17* found under ...\java` | You have only JDK 21 from ACB (rare — ACB ships 17) | Install JDK 17 manually under that folder, or update ACB |
| `AnypointCodeBuilder runtime not found at C:\Users\...\AnypointCodeBuilder\runtime` | Same as above — ACB hasn't pulled the runtime | Open ACB once |
| `Maven build failed (exit 1)` | Compile error in the project (DW parse error, malformed XML, missing dep) | Scroll up for the Maven failure message, fix the source, retry |
| `Env var SFDC_USERNAME is declared in .env but empty` | Empty value for a Salesforce var | Either fill it in `.env` or remove the line |
| Script appears to hang silently before "Starting Mule in console" | `mvn clean package` is downloading deps for the first time on this machine | Wait — first build takes 2–5 minutes; subsequent ones are seconds |

---

## Related

- [`stop-mule.md`](./stop-mule.md) — how to stop a runtime started by this script (or by anything else)
- [`test-sfdc-login.md`](./test-sfdc-login.md) — how to verify Salesforce credentials *outside* of Mule, when this script's runtime fails to log in
- [`../agent-workflow.md`](../agent-workflow.md) § 5 — full secrets-bootstrap explanation, including why `${env.X}` doesn't work in YAML/XML
- [`../../PROJECT_CONTEXT.md`](../../PROJECT_CONTEXT.md) § 7 — current project's secrets-management mechanism per environment
