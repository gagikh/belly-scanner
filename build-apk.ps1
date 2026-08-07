<#
.SYNOPSIS
    Wraps belly-scanner.html in a Capacitor Android project and builds an APK.

.DESCRIPTION
    First run scaffolds everything into .\android-build (a few minutes).
    Every run after that just re-copies the HTML and rebuilds (~20 seconds),
    so the edit -> build -> test loop stays quick.

.EXAMPLE
    .\build-apk.ps1                 # build a debug APK
    .\build-apk.ps1 -Install        # build, then push it to a plugged-in phone
    .\build-apk.ps1 -Clean          # throw away the generated project and start over
    .\build-apk.ps1 -Release        # unsigned release APK (must be signed before Play)
#>

[CmdletBinding()]
param(
    [switch] $Install,
    [switch] $Clean,
    [switch] $Release,
    [string] $AppId     = "com.tummyscanner.app",
    [string] $AppName   = "Tummy Scanner",
    [int]    $TargetSdk = 36
)

$ErrorActionPreference = "Stop"

$Root   = $PSScriptRoot
$Proj   = Join-Path $Root "android-build"
$AndDir = Join-Path $Proj "android"

# the app is a single HTML file; accept either name
$SrcHtml = $null
foreach ($candidate in @("index.html", "belly-scanner.html")) {
    $path = Join-Path $Root $candidate
    if (Test-Path $path) { $SrcHtml = $path; break }
}

function Step($m) { Write-Host "`n==> $m" -ForegroundColor Cyan }
function Info($m) { Write-Host "    $m"    -ForegroundColor DarkGray }
function Warn($m) { Write-Host "    ! $m"  -ForegroundColor Yellow }

function Require-Command([string] $Name, [string] $Hint) {
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "'$Name' was not found on PATH.`n    $Hint"
    }
}

# Always write without a BOM. Node's JSON.parse chokes on a UTF-8 BOM, and
# Set-Content in Windows PowerShell 5.1 adds one by default.
function Write-TextFile([string] $Path, [string] $Text) {
    $enc = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Text, $enc)
}

# Args are passed as an explicit array so PowerShell never tries to interpret
# things like "-y" or "--silent" as parameters of this function.
function Invoke-Npm([string[]] $NpmArgs) {
    & npm.cmd @NpmArgs
    if ($LASTEXITCODE -ne 0) {
        throw "npm $($NpmArgs -join ' ') failed with exit code $LASTEXITCODE"
    }
}

# ---------------------------------------------------------------- checks ----
Step "Checking prerequisites"

if (-not $SrcHtml) { throw "No index.html (or belly-scanner.html) found next to this script." }
Info "app  $(Split-Path $SrcHtml -Leaf)"
Require-Command "node" "Install Node.js 20+ from https://nodejs.org and reopen PowerShell."
Require-Command "npm"  "npm ships with Node.js. Reopen PowerShell after installing it."

$nodeVer   = (& node -v) -replace '^v', ''
$nodeMajor = [int]($nodeVer.Split('.')[0])
if ($nodeMajor -lt 20) { Warn "Node $nodeVer detected. Capacitor wants 20+; the build may fail." }
Info "node v$nodeVer"

# --- Android SDK ---
$Sdk = $env:ANDROID_HOME
if (-not $Sdk) { $Sdk = $env:ANDROID_SDK_ROOT }
if (-not $Sdk) { $Sdk = Join-Path $env:LOCALAPPDATA "Android\Sdk" }
if (-not (Test-Path $Sdk)) {
    throw @"
Android SDK not found.
    Install Android Studio (https://developer.android.com/studio), open it once and
    let it finish downloading the SDK, then reopen PowerShell.
    Or set ANDROID_HOME to an existing SDK folder.
"@
}
Info "SDK  $Sdk"

# --- JDK: Android Studio bundles one, so use that if JAVA_HOME isn't already set ---
if ((-not $env:JAVA_HOME) -or (-not (Test-Path (Join-Path $env:JAVA_HOME "bin\java.exe")))) {
    $jdkGuesses = @(
        (Join-Path ${env:ProgramFiles} "Android\Android Studio\jbr"),
        (Join-Path ${env:ProgramFiles} "Android\Android Studio\jre"),
        (Join-Path $env:LOCALAPPDATA "Programs\Android Studio\jbr"),
        (Join-Path ${env:ProgramFiles} "Eclipse Adoptium\jdk-17*"),
        (Join-Path ${env:ProgramFiles} "Microsoft\jdk-17*")
    )
    foreach ($guess in $jdkGuesses) {
        $hit = @(Get-Item $guess -ErrorAction SilentlyContinue)
        if ($hit.Count -gt 0 -and (Test-Path (Join-Path $hit[0].FullName "bin\java.exe"))) {
            $env:JAVA_HOME = $hit[0].FullName
            break
        }
    }
}
if (-not $env:JAVA_HOME) {
    throw "No JDK found. Install Android Studio (it bundles one), or install JDK 17 and set JAVA_HOME."
}
Info "JDK  $env:JAVA_HOME"

# ----------------------------------------------------------------- clean ----
if ($Clean -and (Test-Path $Proj)) {
    Step "Removing the generated project"
    Remove-Item $Proj -Recurse -Force
}

# --------------------------------------------------------------- scaffold ----
if (-not (Test-Path (Join-Path $Proj "package.json"))) {
    Step "Creating the Capacitor project (first run - this takes a few minutes)"
    New-Item -ItemType Directory -Force -Path $Proj | Out-Null
    Push-Location $Proj
    try {
        Invoke-Npm @('init', '-y')
        Info "Installing Capacitor..."
        Invoke-Npm @('install', '--silent', '@capacitor/core@latest', '@capacitor/android@latest')
        Invoke-Npm @('install', '--silent', '--save-dev', '@capacitor/cli@latest')
    }
    finally { Pop-Location }
}

# --- web assets + config, rewritten every run so edits always land ---
Step "Copying the app"
$www = Join-Path $Proj "www"
New-Item -ItemType Directory -Force -Path $www | Out-Null
Copy-Item $SrcHtml (Join-Path $www "index.html") -Force
Info "$(Split-Path $SrcHtml -Leaf) -> www\index.html"

# androidScheme https gives the WebView a secure origin, which getUserMedia requires.
$config = [ordered]@{
    appId   = $AppId
    appName = $AppName
    webDir  = "www"
    server  = [ordered]@{ androidScheme = "https" }
    android = [ordered]@{
        allowMixedContent           = $false
        backgroundColor             = "#0b1220"
        webContentsDebuggingEnabled = $true
    }
}
Write-TextFile (Join-Path $Proj "capacitor.config.json") ($config | ConvertTo-Json -Depth 5)

# --- add the android platform ---
if (-not (Test-Path $AndDir)) {
    Step "Adding the Android platform"
    Push-Location $Proj
    try { Invoke-Npm @('exec', '--', 'cap', 'add', 'android') }
    finally { Pop-Location }
}

# ------------------------------------------------------- manifest patches ----
Step "Patching the Android manifest"
$manifestPath = Join-Path $AndDir "app\src\main\AndroidManifest.xml"
if (-not (Test-Path $manifestPath)) { throw "AndroidManifest.xml missing - try .\build-apk.ps1 -Clean" }
$manifest = Get-Content $manifestPath -Raw

# Camera + vibrate. Camera and flash are declared optional so the Play listing
# isn't narrowed to devices that have them.
$decls = @(
    @{ key = 'android.permission.CAMERA';        xml = '<uses-permission android:name="android.permission.CAMERA" />' },
    @{ key = 'android.permission.VIBRATE';       xml = '<uses-permission android:name="android.permission.VIBRATE" />' },
    @{ key = 'android.hardware.camera"';         xml = '<uses-feature android:name="android.hardware.camera" android:required="false" />' },
    @{ key = 'android.hardware.camera.flash';    xml = '<uses-feature android:name="android.hardware.camera.flash" android:required="false" />' }
)
$added = @()
foreach ($d in $decls) {
    if ($manifest -notmatch [regex]::Escape($d.key)) {
        $manifest = $manifest -replace '(?=</manifest>)', ("    " + $d.xml + "`r`n")
        $added += ($d.key -replace '"', '').Split('.')[-1]
    }
}
if ($added.Count -gt 0) { Info "added: $($added -join ', ')" } else { Info "permissions already present" }

# Lock to portrait - a scanner you rotate is a scanner you drop.
if ($manifest -notmatch 'android:screenOrientation') {
    $manifest = $manifest -replace '(<activity\b)', ('$1' + "`r`n            android:screenOrientation=""portrait""")
    Info "locked to portrait"
}
Write-TextFile $manifestPath $manifest

# --- target SDK: Play requires 36 for new submissions from 31 Aug 2026 ---
$varsPath = Join-Path $AndDir "variables.gradle"
if (Test-Path $varsPath) {
    $vars   = Get-Content $varsPath -Raw
    $before = $vars
    foreach ($k in @('compileSdkVersion', 'targetSdkVersion')) {
        $m = [regex]::Match($vars, "$k\s*=\s*(\d+)")
        if ($m.Success -and ([int]$m.Groups[1].Value -lt $TargetSdk)) {
            $vars = $vars -replace "$k\s*=\s*\d+", "$k = $TargetSdk"
        }
    }
    if ($vars -ne $before) {
        Write-TextFile $varsPath $vars
        Info "bumped compile/target SDK to $TargetSdk"
    }
    else { Info "SDK levels already at or above $TargetSdk" }
}

# --- app label ---
$stringsPath = Join-Path $AndDir "app\src\main\res\values\strings.xml"
if (Test-Path $stringsPath) {
    $s = Get-Content $stringsPath -Raw
    $s = $s -replace '(<string name="app_name">)[^<]*(</string>)',            ('${1}' + $AppName + '${2}')
    $s = $s -replace '(<string name="title_activity_main">)[^<]*(</string>)', ('${1}' + $AppName + '${2}')
    Write-TextFile $stringsPath $s
}

# --- point gradle at the SDK ---
$sdkEscaped = ($Sdk -replace '\\', '\\\\') -replace ':', '\:'
Write-TextFile (Join-Path $AndDir "local.properties") "sdk.dir=$sdkEscaped`r`n"

# ------------------------------------------------------------------ sync ----
Step "Syncing web assets into the Android project"
Push-Location $Proj
try { Invoke-Npm @('exec', '--', 'cap', 'sync', 'android') }
finally { Pop-Location }

# ----------------------------------------------------------------- build ----
if ($Release) { $task = "assembleRelease"; $variant = "release" }
else          { $task = "assembleDebug";   $variant = "debug"   }

Step "Running gradle $task (the first build downloads a lot; later ones are fast)"
$gradlew = Join-Path $AndDir "gradlew.bat"
& $gradlew "-p" $AndDir $task "--console=plain"
if ($LASTEXITCODE -ne 0) { throw "Gradle build failed with exit code $LASTEXITCODE" }

# ------------------------------------------------------------------ copy ----
$apkDir = Join-Path $AndDir "app\build\outputs\apk\$variant"
$apk = @(Get-ChildItem $apkDir -Filter *.apk -Recurse -ErrorAction SilentlyContinue |
         Sort-Object LastWriteTime -Descending)
if ($apk.Count -eq 0) { throw "Build reported success but no APK was found under $apkDir" }

$dest = Join-Path $Root "tummy-scanner-$variant.apk"
Copy-Item $apk[0].FullName $dest -Force

Step "Done"
Write-Host "    $dest" -ForegroundColor Green
Write-Host "    $([math]::Round($apk[0].Length / 1MB, 1)) MB" -ForegroundColor DarkGray

if ($Release) { Warn "This release APK is UNSIGNED. Sign it before uploading to Google Play." }

# --------------------------------------------------------------- install ----
if ($Install) {
    Step "Installing on the connected phone"
    $adb = Join-Path $Sdk "platform-tools\adb.exe"
    if (-not (Test-Path $adb)) {
        throw "adb not found at $adb - install 'Android SDK Platform-Tools' via Android Studio."
    }

    $devices = @(& $adb devices | Select-Object -Skip 1 | Where-Object { $_ -match '\sdevice\s*$' })
    if ($devices.Count -eq 0) {
        throw @"
No phone detected.
    On the phone: Settings -> About phone -> tap 'Build number' seven times,
    then Settings -> Developer options -> turn on USB debugging.
    Plug it in and accept the 'Allow USB debugging?' prompt.
"@
    }

    & $adb install -r $dest
    if ($LASTEXITCODE -ne 0) { throw "adb install failed." }
    Write-Host "    Installed. Look for '$AppName' in the app drawer." -ForegroundColor Green
}
