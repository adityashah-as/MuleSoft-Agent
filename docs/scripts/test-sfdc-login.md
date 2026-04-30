# `scripts/test-sfdc-login.ps1` — Verify Salesforce Credentials Outside of Mule

> **Task label**: `Salesforce: Test login (.env)`
> **Source**: [`../../scripts/test-sfdc-login.ps1`](../../scripts/test-sfdc-login.ps1)
> **Companion script**: [`run-mule.md`](./run-mule.md)

---

## What it does (one line)

Reads `SFDC_USERNAME` / `SFDC_PASSWORD` / `SFDC_SECURITY_TOKEN` from `.env`, reads the login URL from `src/main/resources/config.yaml` (`sfdc.url`), and POSTs a Salesforce SOAP `login` request directly — no Mule involved. Reports the session id on success or the exact `faultstring` / `exceptionCode` on failure.

If this **fails**, your credentials (or the URL) are wrong — fix them in `.env` / `config.yaml` and don't waste another 90 seconds on a Mule deploy. If this **succeeds**, your credentials are correct and the issue lives somewhere in the `script → -M-D system property → Mule placeholder → Salesforce connector` chain — fix it there, not in the creds.

---

## Why this script exists

When `Mule: Run (Cursor)` deploys but the Salesforce connector reports `INVALID_LOGIN: Invalid username, password, security token`, you have FIVE possible causes simultaneously:

1. Wrong username (e.g. missing `.sandboxname` suffix on a Sandbox org)
2. Wrong password
3. Wrong / outdated security token (Salesforce **resets** the token every time you change your password, and you must email-confirm the new one)
4. Wrong login URL (Sandbox needs `test.salesforce.com`; Prod / Developer Edition / Trailhead Playground need `login.salesforce.com`; My Domain orgs have a custom URL)
5. The Mule script→property→placeholder chain corrupted the value before it reached the connector (trailing whitespace in `.env`, a missing `-M-D` line in `run-mule.ps1`, the wrong `${...}` name in `global-configs.xml`)

This script eliminates causes 1–4 from the picture. If it succeeds, you know the four "outside" causes are NOT to blame, and you can hunt the bug inside the chain.

The Mule deploy loop is **slow** (~60–90s per attempt). This script is **fast** (~2s). So the diagnostic order is always: this script first, Mule second.

---

## When to use it

- Mule deploys but the Salesforce connector fails Test Connection or returns `INVALID_LOGIN` at runtime
- You just rotated the security token (Salesforce → Settings → Reset My Security Token) and want to confirm the new one is in `.env`
- You changed `sfdc.url` in `config.yaml` (e.g. switched from sandbox to prod) and want to confirm the URL is reachable and the user can log in there
- A teammate just gave you their `.env` values and you want to sanity-check before running anything else
- You're not sure whether a Salesforce-related Mule error is "the creds are wrong" or "the Mule wiring is wrong"

It's also a good first step **before** the agent suggests the rest of the bootstrap — if creds don't even pass this script, no amount of XML editing will fix Mule.

---

## Pre-flight checklist

| Requirement | How to verify | If missing |
|---|---|---|
| `.env` exists at project root | `Test-Path .env` returns `True` | Copy `.env.example` → `.env` and fill values |
| `.env` has all three SFDC vars filled in | Open `.env` and confirm `SFDC_USERNAME`, `SFDC_PASSWORD`, `SFDC_SECURITY_TOKEN` are non-empty | Get the credentials from your Salesforce org (the security token comes via email after Reset My Security Token) |
| `src/main/resources/config.yaml` has `sfdc.url` set | `Select-String -Path src/main/resources/config.yaml -Pattern '^\s*url:'` shows a line with a `https://...` URL | Add it under `sfdc:` — see template in [`run-mule.md`](./run-mule.md) |
| Outbound HTTPS to `*.salesforce.com` is allowed from your network | `curl https://login.salesforce.com -I` returns `200`/`302` | Whitelist `*.salesforce.com` in your corporate proxy / firewall |
| PowerShell can make web requests (TLS 1.2+) | `Invoke-RestMethod -Uri https://login.salesforce.com -Method GET` succeeds | Update PowerShell or run `[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12` first |

---

## What it does — step by step (with line refs)

### Step 1 — Load `.env` (lines 22–42)

```22:42:scripts/test-sfdc-login.ps1
$envFile = Join-Path $projectRoot '.env'
if (-not (Test-Path $envFile)) { Write-Error ".env not found at $envFile" }

Get-Content $envFile | ForEach-Object {
  if ($_ -match '^\s*#') { return }
  if ($_ -match '^\s*$') { return }
  if ($_ -match '^\s*([^=]+?)\s*=\s*(.*?)\s*$') {
    Set-Item -Path "Env:$($matches[1].Trim())" -Value $matches[2].Trim()
  }
}

$user = $env:SFDC_USERNAME
$pass = $env:SFDC_PASSWORD
$tok  = $env:SFDC_SECURITY_TOKEN

foreach ($pair in @{ SFDC_USERNAME=$user; SFDC_PASSWORD=$pass; SFDC_SECURITY_TOKEN=$tok }.GetEnumerator()) {
  if ([string]::IsNullOrWhiteSpace($pair.Value)) {
    Write-Error "$($pair.Key) is empty in .env"
  }
  Write-Host ("{0,-22} length = {1}" -f $pair.Key, $pair.Value.Length)
}
```

- Reuses the same `.env` parser as `run-mule.ps1` (skip comments / blanks; trim whitespace; `KEY=VALUE` → process env var).
- Hard-fails immediately if `.env` is missing — no point continuing.
- Hard-fails if any of the three vars is empty / whitespace.
- Prints **lengths only** (never values) — so you can spot "I forgot the trailing characters of the token" or "this value has leading whitespace I didn't see in `.env`" without leaking secrets to the terminal.

### Step 2 — Read the login URL from `config.yaml` (lines 44–55)

```44:55:scripts/test-sfdc-login.ps1
$configYaml = Join-Path $projectRoot 'src\main\resources\config.yaml'
$urlLine    = Select-String -Path $configYaml -Pattern '^\s*url:\s*"?([^"\s]+)"?' | Select-Object -First 1
if (-not $urlLine) { Write-Error "Could not find sfdc.url in $configYaml" }
$loginUrl   = $urlLine.Matches[0].Groups[1].Value
Write-Host ""
Write-Host "Login URL: $loginUrl"
$envHint    = if ($loginUrl -match 'test\.salesforce\.com') { 'SANDBOX' }
              elseif ($loginUrl -match 'login\.salesforce\.com') { 'PRODUCTION' }
              else { 'CUSTOM' }
Write-Host "Org type:  $envHint"
```

- Greps `config.yaml` for the first line matching `<spaces>url: <maybe-quoted-url>` — assumes the URL lives under the `sfdc:` block. (If your project uses a different YAML structure, the regex may need tightening — but for the agent-scaffolded layout it's reliable.)
- Classifies the URL: `test.salesforce.com` → SANDBOX, `login.salesforce.com` → PRODUCTION, anything else → CUSTOM (most often a My Domain URL).
- Prints both — if you see "PRODUCTION" but you intended a sandbox, stop here and fix `config.yaml` before going further.

### Step 3 — Build the SOAP login envelope (lines 57–71)

```57:71:scripts/test-sfdc-login.ps1
function Encode-Xml($s) { [System.Security.SecurityElement]::Escape($s) }
$soap = @"
<?xml version="1.0" encoding="utf-8" ?>
<env:Envelope xmlns:xsd="http://www.w3.org/2001/XMLSchema"
              xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
              xmlns:env="http://schemas.xmlsoap.org/soap/envelope/">
  <env:Body>
    <n1:login xmlns:n1="urn:partner.soap.sforce.com">
      <n1:username>$(Encode-Xml $user)</n1:username>
      <n1:password>$(Encode-Xml ($pass + $tok))</n1:password>
    </n1:login>
  </env:Body>
</env:Envelope>
"@
```

- Uses the **Salesforce Partner SOAP API** `login` operation — the same one the Mule connector uses under the hood for username/password auth.
- The two values are XML-escaped to avoid breaking the envelope if your password / username contains `<`, `>`, `&`, or `"`.
- **`<n1:password>` is `password + token` concatenated.** This is the single Salesforce-specific gotcha: the SOAP login API does NOT take the security token as a separate field; you append it to the password. (This is true even though Mule's `<sfdc:basic-connection>` exposes them as separate XML attributes — the connector concatenates them internally before sending.)

### Step 4 — POST and report (lines 73–121)

```73:94:scripts/test-sfdc-login.ps1
Write-Host "Calling Salesforce SOAP login..."
try {
  $response = Invoke-RestMethod -Uri $loginUrl -Method POST `
    -Body $soap `
    -ContentType 'text/xml; charset=UTF-8' `
    -Headers @{ 'SOAPAction' = 'login' }

  $sessionId = $response.Envelope.Body.loginResponse.result.sessionId
  $serverUrl = $response.Envelope.Body.loginResponse.result.serverUrl
  $userId    = $response.Envelope.Body.loginResponse.result.userId
  ...
```

On **success** the script prints:

```
==================== LOGIN OK ====================
User Id:    005XX0000012345AAA
Server URL: https://acme--dev1.sandbox.my.salesforce.com/services/Soap/u/59.0/00DXX0000004ABCDEF
Session Id: 00DXX0000004ABC!AQ8AQ...
==================================================

These credentials WORK against Salesforce.
If Mule still rejects them, the issue is somewhere in the script -> system property -> Mule placeholder chain (not the creds).
```

- Only the first 20 chars of the session id are shown — don't paste the script output into a public chat anyway, but the truncation reduces blast radius.
- The `Server URL` is informative: it confirms which org / pod the user actually logged into. If you intended Sandbox but `Server URL` doesn't contain `.sandbox.` or your sandbox name, you're hitting the wrong tenant.

On **failure** (lines 95–121) the script catches the `WebException`, reads the SOAP fault out of the response body, and prints:

```
==================== LOGIN FAILED ====================
HTTP status: 500 Server Error

faultstring: INVALID_LOGIN: Invalid username, password, security token; or user locked out.
exceptionCode: INVALID_LOGIN

Common causes:
  1. Wrong security token (most common) - resets every time you change password
  2. Wrong URL - sandbox needs test.salesforce.com, prod needs login.salesforce.com
  3. Username missing the sandbox suffix (e.g. you@company.com.dev1)
  4. Trailing whitespace in .env values
  5. API access not enabled on this user profile
==================================================
```

The `faultstring` and `exceptionCode` come straight from Salesforce's SOAP fault — they are the canonical, debuggable answer. Whatever they say is what's actually wrong.

---

## How to run it

### Recommended — via the task

`Ctrl+Shift+P` → `Tasks: Run Task` → **Salesforce: Test login (.env)**

Output streams to a dedicated panel and the panel is cleared on each run.

### Direct invocation

```powershell
pwsh ./scripts/test-sfdc-login.ps1
```

---

## Interpreting the result

### LOGIN OK

Your credentials are correct and the URL is correct. If Mule's connector still rejects them at runtime, the bug is in **the chain**, not the creds. Walk the chain in order:

1. **`.env`** — open it and confirm there's no trailing whitespace on the values (the script uses `Set-Item Env:` with already-trimmed values, so `.env` parsing is fine, but a downstream tool may not trim).
2. **`scripts/run-mule.ps1`** lines 117–122 — confirm there is a `-M-D<placeholder>=...` line for **each** of `sfdc.username`, `sfdc.password`, `sfdc.token` (or whatever your placeholder names are).
3. **`global-configs.xml`** — confirm the `<sfdc:basic-connection>` (or whichever auth element you use) references **`${sfdc.username}`** etc. — NOT `${env.SFDC_USERNAME}`. Mule does not auto-resolve `${env.X}` to OS env vars (see [`../agent-workflow.md`](../agent-workflow.md) § 5).
4. **`config.yaml`** — confirm the `sfdc.url` here matches the URL the script logged in against. If the script and Mule disagree on URL, you've configured them in different places.
5. After fixing, re-run **Mule: Run (Cursor)** and watch for the Salesforce-config Test Connection result.

### LOGIN FAILED — `INVALID_LOGIN`

This is by far the most common failure. Run through the five common-causes list at the bottom of the script's output, in order:

1. **Wrong security token** — you (or someone) changed the password recently. Reset the token in Salesforce (Setup → Personal Information → Reset My Security Token), check email, paste the new token into `.env`, re-run this script.
2. **Wrong URL** — the script told you SANDBOX/PRODUCTION/CUSTOM at the top. Compare against what the user is from. (Developer Edition orgs from developer.salesforce.com use the **production** endpoint — common confusion.)
3. **Sandbox username suffix** — sandbox usernames have a `.<sandboxname>` suffix (e.g. `someone@company.com.dev1`). If `.env` has the production username for a sandbox org, login fails.
4. **Trailing whitespace** — re-open `.env` in a text editor that shows trailing spaces. The script's parser trims, but if you copied from a Word doc / email and there's a tab character mid-value, it could survive. Length printed on each var helps spot this.
5. **API access disabled** — the user's Salesforce profile must have API Enabled. Setup → Profiles → Permissions tab → confirm "API Enabled" is checked.

### LOGIN FAILED — `LOGIN_MUST_USE_SECURITY_TOKEN`

Same as INVALID_LOGIN but more specific — it means you're logging in from an IP the org hasn't whitelisted, AND the token is being sent but is wrong. Reset the token.

### LOGIN FAILED — `PASSWORD_LOCKOUT`

You (or someone) tried wrong creds too many times. Wait 15 minutes, or have the org admin unlock the user. Don't keep retrying with the same wrong creds — you're making it worse.

### LOGIN FAILED — `INVALID_OPERATION_WITH_EXPIRED_PASSWORD`

The password expired. Log into Salesforce in a browser to reset it, then update `.env` (and reset the token, since it changed too).

### Could not find sfdc.url in src/main/resources/config.yaml

Either the YAML doesn't have an `sfdc:` block at all, or its structure is unusual and the script's regex doesn't match. Add (or fix):

```yaml
sfdc:
  url: "https://test.salesforce.com/services/Soap/u/59.0"
```

…then re-run.

### `.env not found` / `<VAR> is empty in .env`

Self-explanatory — fix the file.

### TLS / connection errors (`Could not establish trust relationship`, `Unable to connect to the remote server`)

- Corporate proxy — set `$env:HTTPS_PROXY` before running, or use `Invoke-WebRequest -Proxy ...` (the script doesn't expose proxy settings; you'd have to edit it).
- Old PowerShell on a Win10 machine — force TLS 1.2 first: `[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12`
- Firewall blocks `*.salesforce.com` — ask IT to whitelist.

---

## What this script does **not** do

- Doesn't test OAuth / OAuth JWT auth — only username + password + token. If your org uses OAuth JWT, the right test is a manual `curl` against `/services/oauth2/token` with your assertion. (Could be added — the script is intentionally minimal.)
- Doesn't validate that any specific SObject (`Account`, `Contact`, `Opportunity__c`) is reachable to the user. A `LOGIN OK` only proves the user can authenticate; permission errors per object surface only when the connector actually performs an operation. Use ACB → `global-configs.xml` → click the Salesforce config → **Test Connection** for that — it does an authenticated `describeGlobal()` call.
- Doesn't write the session id anywhere — the value is discarded. (Salesforce sessions are tied to the issuing IP and have a default lifetime of 2 hours; there's no point caching a one-shot diagnostic session.)
- Doesn't touch Mule. That's the entire point — orthogonal to the Mule pipeline so you can isolate the failure.

---

## Related

- [`run-mule.md`](./run-mule.md) — the script you'll run after this one passes
- [`../agent-workflow.md`](../agent-workflow.md) § 5 — why `${env.X}` doesn't work in Mule YAML/XML and what does
- `../../.cursor/rules/mule-salesforce.mdc` § "CRITICAL: pick the right login endpoint per org type" — the canonical table of which URL goes with which org type
- `../../.cursor/rules/mule-salesforce.mdc` § 8 — the SF `statusCode` → HTTP status mapping the agent uses in error handlers
