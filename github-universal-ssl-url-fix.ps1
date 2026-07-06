# =====================================================================
# UNIVERSAL URL CONNECTIVITY + SSL RESET TOOL v4
# GitHub-hosted PowerShell. Target URL/domain is entered manually.
# Windows PowerShell 5.1 compatible.
# =====================================================================

param(
    [string]$Target = ""
)

$ErrorActionPreference = "Continue"

function Write-Step {
    param([string]$Text)
    Write-Host ""
    Write-Host $Text -ForegroundColor Cyan
}

function Write-Ok {
    param([string]$Text)
    Write-Host "  OK   $Text" -ForegroundColor Green
}

function Write-Skip {
    param([string]$Text)
    Write-Host "  SKIP $Text" -ForegroundColor DarkYellow
}

function Normalize-Target {
    param([string]$InputText)

    if ([string]::IsNullOrWhiteSpace($InputText)) {
        return $null
    }

    $value = $InputText.Trim().Trim('"').Trim("'")

    if ([string]::IsNullOrWhiteSpace($value)) {
        return $null
    }

    # Convert common pasted inputs to a clean URL.
    $value = $value -replace '^www\.', 'www.'

    # If the user enters only a domain/path, default to HTTPS.
    if ($value -notmatch '^[a-zA-Z][a-zA-Z0-9+\-.]*://') {
        $value = "https://$value"
    }

    $uri = $null
    if (-not [System.Uri]::TryCreate($value, [System.UriKind]::Absolute, [ref]$uri)) {
        return $null
    }

    if ([string]::IsNullOrWhiteSpace($uri.Host)) {
        return $null
    }

    if ($uri.Scheme -ne "http" -and $uri.Scheme -ne "https") {
        return $null
    }

    return $uri
}

function Get-TargetPort {
    param([System.Uri]$Uri)

    if (-not $Uri.IsDefaultPort) {
        return [int]$Uri.Port
    }

    if ($Uri.Scheme -eq "http") {
        return 80
    }

    return 443
}

function Test-IsAdmin {
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    catch {
        return $false
    }
}

function Invoke-SafeCommand {
    param(
        [string]$Label,
        [scriptblock]$Command
    )

    try {
        & $Command
        Write-Ok $Label
    }
    catch {
        Write-Skip ("{0} - {1}" -f $Label, $_.Exception.Message)
    }
}

# Self-elevate if someone directly runs the PS1 instead of the BAT.
if (-not (Test-IsAdmin)) {
    Write-Host "Requesting Administrator permission..." -ForegroundColor Yellow

    $argLine = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    if (-not [string]::IsNullOrWhiteSpace($Target)) {
        $escapedTarget = $Target.Replace('"', '\"')
        $argLine = "$argLine -Target `"$escapedTarget`""
    }

    try {
        Start-Process -FilePath "powershell.exe" -ArgumentList $argLine -Verb RunAs
    }
    catch {
        Write-Host "Failed to relaunch as Administrator: $($_.Exception.Message)" -ForegroundColor Red
        Read-Host "Press Enter to exit"
    }
    exit
}

Clear-Host
Write-Host ""
Write-Host "=== UNIVERSAL URL CONNECTIVITY + SSL RESET TOOL v4 ===" -ForegroundColor Green
Write-Host "Enter any website URL/domain manually. No hardcoded target domain." -ForegroundColor Yellow
Write-Host ""

$Uri = Normalize-Target $Target
while ($null -eq $Uri) {
    $inputUrl = Read-Host "Enter URL or domain, example console.panget.in or https://example.com"
    $Uri = Normalize-Target $inputUrl
    if ($null -eq $Uri) {
        Write-Host "Invalid URL/domain. Use only http/https website URLs or domains." -ForegroundColor Red
    }
}

$TargetUrl  = $Uri.AbsoluteUri
$TargetHost = $Uri.Host
$TargetPort = Get-TargetPort $Uri

Write-Host "Target URL : $TargetUrl" -ForegroundColor Yellow
Write-Host "Target Host: $TargetHost" -ForegroundColor Yellow
Write-Host ("Target Port: {0}" -f $TargetPort) -ForegroundColor Yellow
Write-Host ""

$continue = Read-Host "This will close browsers and reset DNS/SSL/network cache. Continue? (Y/N)"
if ($continue -notmatch '^(y|yes)$') {
    Write-Host "Cancelled." -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit
}

$Users = @()
try {
    $Users = Get-ChildItem "C:\Users" -Directory -ErrorAction SilentlyContinue | Where-Object {
        $_.Name -notin @("Public", "Default", "Default User", "All Users", "desktop.ini")
    }
}
catch {}

Write-Step "[1/10] Closing browsers..."
foreach ($browser in @("chrome", "msedge", "firefox", "brave", "opera", "iexplore")) {
    Stop-Process -Name $browser -Force -ErrorAction SilentlyContinue
}
Start-Sleep -Seconds 2
Write-Ok "Browsers closed if they were running"

Write-Step "[2/10] Flushing DNS cache..."
Invoke-SafeCommand "ipconfig /flushdns" { ipconfig /flushdns | Out-Null }
Invoke-SafeCommand "Clear-DnsClientCache" { Clear-DnsClientCache -ErrorAction Stop }

Write-Step "[3/10] Resetting Windows SSL state and certificate URL cache..."
Invoke-SafeCommand "Windows SSL state cleared" {
    Start-Process -FilePath "rundll32.exe" -ArgumentList "InetCpl.cpl,ClearMyTracksByProcess 8" -Wait -WindowStyle Hidden
}
Invoke-SafeCommand "Certificate URL cache cleared" {
    certutil -urlcache * delete | Out-Null
}

Write-Step "[4/10] Resetting WinHTTP proxy..."
Invoke-SafeCommand "WinHTTP proxy reset" { netsh winhttp reset proxy | Out-Null }

Write-Step "[5/10] Clearing browser SSL/HSTS/cache files..."
foreach ($User in $Users) {
    $Base = $User.FullName

    $ChromiumRoots = @(
        "$Base\AppData\Local\Google\Chrome\User Data",
        "$Base\AppData\Local\Microsoft\Edge\User Data",
        "$Base\AppData\Local\BraveSoftware\Brave-Browser\User Data",
        "$Base\AppData\Local\Chromium\User Data"
    )

    foreach ($Root in $ChromiumRoots) {
        if (Test-Path $Root) {
            Get-ChildItem $Root -Directory -ErrorAction SilentlyContinue | Where-Object {
                $_.Name -eq "Default" -or $_.Name -like "Profile *"
            } | ForEach-Object {
                $Profile = $_.FullName
                $Items = @(
                    "$Profile\TransportSecurity",
                    "$Profile\Network\TransportSecurity",
                    "$Profile\Network\Reporting and NEL",
                    "$Profile\Network\Network Persistent State",
                    "$Profile\Cache\*",
                    "$Profile\Code Cache\*",
                    "$Profile\GPUCache\*"
                )
                foreach ($Item in $Items) {
                    Remove-Item $Item -Force -Recurse -ErrorAction SilentlyContinue
                }
            }
        }
    }

    $FirefoxLocal = "$Base\AppData\Local\Mozilla\Firefox\Profiles"
    if (Test-Path $FirefoxLocal) {
        Get-ChildItem $FirefoxLocal -Directory -ErrorAction SilentlyContinue | ForEach-Object {
            Remove-Item "$($_.FullName)\cache2\*" -Force -Recurse -ErrorAction SilentlyContinue
            Remove-Item "$($_.FullName)\startupCache\*" -Force -Recurse -ErrorAction SilentlyContinue
        }
    }

    $FirefoxRoaming = "$Base\AppData\Roaming\Mozilla\Firefox\Profiles"
    if (Test-Path $FirefoxRoaming) {
        Get-ChildItem $FirefoxRoaming -Directory -ErrorAction SilentlyContinue | ForEach-Object {
            Remove-Item "$($_.FullName)\SiteSecurityServiceState.txt" -Force -ErrorAction SilentlyContinue
        }
    }

    $OperaItems = @(
        "$Base\AppData\Local\Opera Software\Opera Stable\Cache\*",
        "$Base\AppData\Local\Opera Software\Opera Stable\Code Cache\*",
        "$Base\AppData\Roaming\Opera Software\Opera Stable\TransportSecurity"
    )
    foreach ($Item in $OperaItems) {
        Remove-Item $Item -Force -Recurse -ErrorAction SilentlyContinue
    }
}
Write-Ok "Browser SSL/HSTS/cache cleanup completed"

Write-Step "[6/10] Setting Google DNS on active adapters..."
try {
    if (Get-Command Get-NetAdapter -ErrorAction SilentlyContinue) {
        $Adapters = Get-NetAdapter -ErrorAction Stop | Where-Object { $_.Status -eq "Up" }
        foreach ($Adapter in $Adapters) {
            try {
                Set-DnsClientServerAddress -InterfaceIndex $Adapter.InterfaceIndex -ServerAddresses @("8.8.8.8", "8.8.4.4") -ErrorAction Stop
                Write-Ok ("DNS set on {0}" -f $Adapter.Name)
            }
            catch {
                Write-Skip ("DNS not changed on {0} - {1}" -f $Adapter.Name, $_.Exception.Message)
            }
        }
    }
    else {
        Write-Skip "Get-NetAdapter not available on this Windows version"
    }
}
catch {
    Write-Skip ("DNS adapter update skipped - {0}" -f $_.Exception.Message)
}

Write-Step "[7/10] Resetting Winsock and TCP/IP stack..."
Invoke-SafeCommand "Winsock reset" { netsh winsock reset | Out-Null }
Invoke-SafeCommand "TCP/IP reset" { netsh int ip reset | Out-Null }

Write-Step "[8/10] Testing DNS for $TargetHost..."
try {
    $DNS = $null
    if (Get-Command Resolve-DnsName -ErrorAction SilentlyContinue) {
        $DNS = Resolve-DnsName $TargetHost -Server 8.8.8.8 -ErrorAction Stop
        Write-Host "DNS Resolution: OK" -ForegroundColor Green
        $DNS | Where-Object { $_.IPAddress } | Select-Object -ExpandProperty IPAddress -Unique | ForEach-Object {
            Write-Host "  IP: $_"
        }
    }
    else {
        nslookup $TargetHost 8.8.8.8
    }
}
catch {
    Write-Host "DNS Resolution: FAILED" -ForegroundColor Red
    Write-Host ("  {0}" -f $_.Exception.Message) -ForegroundColor DarkYellow
}

Write-Step ("[9/10] Testing TCP port {0} for {1}..." -f $TargetPort, $TargetHost)
try {
    $TcpOk = $false
    if (Get-Command Test-NetConnection -ErrorAction SilentlyContinue) {
        $Conn = Test-NetConnection $TargetHost -Port $TargetPort -WarningAction SilentlyContinue
        $TcpOk = [bool]$Conn.TcpTestSucceeded
    }
    else {
        $Client = New-Object System.Net.Sockets.TcpClient
        $Async = $Client.BeginConnect($TargetHost, $TargetPort, $null, $null)
        $TcpOk = $Async.AsyncWaitHandle.WaitOne(5000, $false)
        if ($TcpOk) { $Client.EndConnect($Async) }
        $Client.Close()
    }

    if ($TcpOk) {
        Write-Host ("TCP Port {0}: OK" -f $TargetPort) -ForegroundColor Green
    }
    else {
        Write-Host ("TCP Port {0}: FAILED" -f $TargetPort) -ForegroundColor Red
    }
}
catch {
    Write-Host ("TCP Port {0}: FAILED" -f $TargetPort) -ForegroundColor Red
    Write-Host ("  {0}" -f $_.Exception.Message) -ForegroundColor DarkYellow
}

Write-Step "[10/10] Testing web request and opening target..."
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
}
catch {}

try {
    $Response = Invoke-WebRequest -Uri $TargetUrl -UseBasicParsing -TimeoutSec 20 -ErrorAction Stop
    Write-Host ("Web Request: OK, HTTP {0}" -f $Response.StatusCode) -ForegroundColor Green
}
catch {
    Write-Host "Web Request: FAILED" -ForegroundColor Red
    Write-Host ("  {0}" -f $_.Exception.Message) -ForegroundColor DarkYellow
    Write-Host ""
    Write-Host "Important:" -ForegroundColor Yellow
    Write-Host "If the browser shows NET::ERR_CERT_COMMON_NAME_INVALID or a certificate name mismatch," -ForegroundColor Yellow
    Write-Host "the server certificate is wrong for this domain. A local reset cannot fix that." -ForegroundColor Yellow
}

try {
    Start-Process $TargetUrl
}
catch {}

Write-Host ""
Write-Host "DONE." -ForegroundColor Green
Write-Host "Restart the PC once if the website still fails after this reset." -ForegroundColor Yellow
Write-Host ""
Read-Host "Press Enter to exit"
