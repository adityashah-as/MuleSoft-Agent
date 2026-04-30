<#
.SYNOPSIS
  Local-dev Mule runner for Cursor (no ACB debug adapter required).

.DESCRIPTION
  1. Loads .env into the current process
  2. Builds the app with Maven
  3. Copies the packaged jar into the standalone runtime apps folder
  4. Sets MULE_OPTS with -D system properties for Salesforce credentials
  5. Starts the Mule runtime in console mode (Ctrl+C to stop)

  Auto-discovers the latest mule-enterprise-standalone-* under ~/AnypointCodeBuilder/runtime.

.NOTES
  Run via the Cursor task "Run Mule (Cursor)" or directly: pwsh ./scripts/run-mule.ps1
#>

$ErrorActionPreference = 'Stop'

function Write-Step($msg) { Write-Host "==> $msg" -ForegroundColor Cyan }

$projectRoot = Resolve-Path (Join-Path $PSScriptRoot '..')

# ---------------- 1. Load .env ----------------
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

  # Only flag SFDC vars if .env declares them but leaves them blank.
  # If a project doesn't use Salesforce at all, the loop is silent.
  foreach ($req in @('SFDC_USERNAME','SFDC_PASSWORD','SFDC_SECURITY_TOKEN')) {
    $declared = Get-Item "Env:$req" -ErrorAction SilentlyContinue
    if ($declared -and -not $declared.Value) {
      Write-Error "Env var $req is declared in .env but empty. Fill it in or remove the line."
    }
  }
} else {
  Write-Warning ".env not found at $envFile - continuing without it. If your flows reference `${...} properties (e.g. `${sfdc.username}), the runtime will fail at deploy with PropertyNotFoundException. Create .env in the project root and re-run."
}

# ---------------- 2a. Pin JAVA_HOME to ACB's bundled JDK ----------------
# Mule 4.8.x supports up to JDK 17; the system default may be JDK 21 which is unsupported.
$jdkBase = Join-Path $env:USERPROFILE 'AnypointCodeBuilder\java'
if (-not (Test-Path $jdkBase)) {
  Write-Error "ACB JDK folder not found at $jdkBase. Install Anypoint Code Builder runtime."
}
$jdk = Get-ChildItem -Directory $jdkBase |
  Where-Object Name -like 'jdk-17*' |
  Sort-Object Name -Descending |
  Select-Object -First 1
if (-not $jdk) {
  Write-Error "No jdk-17* found under $jdkBase. Mule 4.8.x requires JDK 17."
}
$env:JAVA_HOME = $jdk.FullName
$env:PATH = (Join-Path $jdk.FullName 'bin') + ';' + $env:PATH
Write-Step "JAVA_HOME = $env:JAVA_HOME"

# ---------------- 2b. Discover runtime ----------------
$runtimeBase = Join-Path $env:USERPROFILE 'AnypointCodeBuilder\runtime'
if (-not (Test-Path $runtimeBase)) {
  Write-Error "AnypointCodeBuilder runtime not found at $runtimeBase"
}
$runtime = Get-ChildItem -Directory $runtimeBase |
  Where-Object Name -like 'mule-enterprise-standalone-*' |
  Sort-Object Name -Descending |
  Select-Object -First 1
if (-not $runtime) {
  Write-Error "No mule-enterprise-standalone-* runtime found under $runtimeBase"
}
Write-Step "Using runtime: $($runtime.FullName)"

# ---------------- 3. Build ----------------
Push-Location $projectRoot
try {
  Write-Step "mvn clean package -DskipTests"
  & mvn clean package -DskipTests
  if ($LASTEXITCODE -ne 0) { throw "Maven build failed (exit $LASTEXITCODE)" }

  $jar = Get-ChildItem (Join-Path $projectRoot 'target') -Filter '*-mule-application.jar' |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
  if (-not $jar) { throw "No *-mule-application.jar found in target/. Did the build succeed?" }
  Write-Step "Packaged: $($jar.Name)"

  # ---------------- 4. Deploy ----------------
  # A fresh standalone runtime ships WITHOUT an apps/ folder. PowerShell's
  # Copy-Item with a non-existent destination creates a FILE at that path,
  # which then poisons the runtime (NotDirectoryException on next start).
  # So: ensure apps/ exists as a directory, and always copy with an explicit
  # destination filename.
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

  # ---------------- 5. Build system-property args ----------------
  # mule.bat overwrites $env:MULE_OPTS internally, so we pass system properties
  # as command-line args using the -M-D<prop>=<value> syntax. launcher.bat
  # forwards these through mule-wrapper-additional-parameters-parser.jar so the
  # spawned JVM receives them as -D<prop>=<value>.
  $muleArgs = @(
    'console',
    "-M-Dsfdc.username=$($env:SFDC_USERNAME)",
    "-M-Dsfdc.password=$($env:SFDC_PASSWORD)",
    "-M-Dsfdc.token=$($env:SFDC_SECURITY_TOKEN)"
  )
  Write-Step "Forwarding sfdc.* as -M-D system properties"

  # ---------------- 6. Run ----------------
  $muleBat = Join-Path $runtime.FullName 'bin\mule.bat'
  Write-Step "Starting Mule in console (Ctrl+C to stop)..."
  Write-Host ""
  & $muleBat @muleArgs
}
finally {
  Pop-Location
}
