# =====================================================================
# UNIVERSAL URL CONNECTIVITY + SSL RESET TOOL
# - GitHub-hosted script; target URL/domain is entered manually
# - Enter any URL or domain at runtime
# - Run as Administrator
# - Flushes DNS cache
# - Clears Windows SSL state
# - Clears certificate URL cache
# - Clears browser SSL/HSTS/cache data
# - Optional Google DNS reset
# - Resets Winsock/TCP/IP and WinHTTP proxy
# - Tests DNS + HTTP/HTTPS ports
# - Opens the entered URL
# =====================================================================

param(
    [string]$Target = ""
)

function Normalize-Target {
    param([string]$InputText)

    $value = ($InputText | ForEach-Object { $_.Trim() })
    if ([string]::IsNullOrWhiteSpace($value)) { return $null }

    # Remove surrounding quotes
    $value = $value.Trim('"').Trim("'")

    # If only a domain is given, default to https://
    if ($value -notmatch '^[a-zA-Z][a-zA-Z0-9+.-]*://') {
        $value = "https://$value"
    }

    try {
        $uri = [System.Uri]$value
        if ([string]::IsNullOrWhiteSpace($uri.Host)) { return $null }
        return $uri
    }
    catch {
        return $null
    }
}

function Write-Step {
    param([string]$Text)
    Write-Host ""
    Write-Host $Text -ForegroundColor Cyan
}

# Self-elevate. Preserve optional target argument.
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)) {
    $argLine = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    if (-not [string]::IsNullOrWhiteSpace($Target)) {
        $safeTarget = $Target.Replace('"','\"')
        $argLine += " -Target `"$safeTarget`""
    }
    Start-Process powershell.exe -ArgumentList $argLine -Verb RunAs
    exit
}

Clear-Host
Write-Host ""
Write-Host "=== UNIVERSAL URL CONNECTIVITY + SSL RESET TOOL ===" -ForegroundColor Green
Write-Host "GitHub-hosted. Enter any URL/domain manually." -ForegroundColor Yellow
Write-Host ""

$Uri = Normalize-Target $Target
while ($null -eq $Uri) {
    $inputUrl = Read-Host "Enter URL or domain, example console.panget.in or https://example.com"
    $Uri = Normalize-Target $inputUrl
    if ($null -eq $Uri) {
        Write-Host "Invalid URL/domain. Try again." -ForegroundColor Red
    }
}

$TargetUrl  = $Uri.AbsoluteUri
$TargetHost = $Uri.Host
$TargetPort = if ($Uri.IsDefaultPort) { if ($Uri.Scheme -eq "http") { 80 } else { 443 } } else { $Uri.Port }

Write-Host "Target URL : $TargetUrl" -ForegroundColor Yellow
Write-Host "Target Host: $TargetHost" -ForegroundColor Yellow
Write-Host "Target Port: $TargetPort" -ForegroundColor Yellow
Write-Host ""

$continue = Read-Host "This will close browsers and reset DNS/SSL/network cache. Continue? (Y/N)"
if ($continue -notmatch '^(y|yes)$') {
    Write-Host "Cancelled." -ForegroundColor Red
    Start-Sleep -Seconds 1
    exit
}

$Users = Get-ChildItem C:\Users -Directory -ErrorAction SilentlyContinue |
Where-Object {
    $_.Name -notin @("Public", "Default", "Default User", "All Users")
}

Write-Step "[1/11] Closing browsers..."
"chrome","msedge","firefox","brave","opera","iexplore" | ForEach-Object {
    Stop-Process -Name $_ -Force -ErrorAction SilentlyContinue
}
Start-Sleep -Seconds 2

Write-Step "[2/11] Setting Google DNS on active network adapters..."
try {
    Get-NetAdapter -ErrorAction Stop |
    Where-Object { $_.Status -eq "Up" } |
    ForEach-Object {
        try {
            Set-DnsClientServerAddress `
                -InterfaceIndex $_.InterfaceIndex `
                -ServerAddresses ("8.8.8.8","8.8.4.4") `
                -ErrorAction Stop
            Write-Host "  OK  $($_.Name)"
        }
        catch {
            Write-Host "  SKIP $($_.Name) - $($_.Exception.Message)" -ForegroundColor DarkYellow
        }
    }
}
catch {
    Write-Host "  DNS adapter update skipped: $($_.Exception.Message)" -ForegroundColor DarkYellow
}

Write-Step "[3/11] Enabling Secure DNS / DoH for Chromium browsers..."
$Policies = @(
    "HKLM:\SOFTWARE\Policies\Google\Chrome",
    "HKLM:\SOFTWARE\Policies\Microsoft\Edge",
    "HKLM:\SOFTWARE\Policies\BraveSoftware\Brave",
    "HKLM:\SOFTWARE\Policies\Chromium"
)

foreach ($Policy in $Policies) {
    try {
        New-Item $Policy -Force | Out-Null
        New-ItemProperty -Path $Policy -Name DnsOverHttpsMode -Value secure -PropertyType String -Force | Out-Null
        New-ItemProperty -Path $Policy -Name DnsOverHttpsTemplates -Value "https://dns.google/dns-query" -PropertyType String -Force | Out-Null
    }
    catch {}
}

Write-Step "[4/11] Configuring Firefox Secure DNS..."
foreach ($User in $Users) {
    $ProfileRoot = "$($User.FullName)\AppData\Roaming\Mozilla\Firefox\Profiles"
    if (Test-Path $ProfileRoot) {
        Get-ChildItem $ProfileRoot -Directory -ErrorAction SilentlyContinue |
        ForEach-Object {
            $UserJS = Join-Path $_.FullName "user.js"
            @'
user_pref("network.trr.mode", 3);
user_pref("network.trr.uri", "https://dns.google/dns-query");
user_pref("network.trr.bootstrapAddress", "8.8.8.8");
user_pref("network.trr.confirmationNS", "skip");
'@ | Add-Content $UserJS -Encoding UTF8
        }
    }
}

Write-Step "[5/11] Flushing DNS cache..."
ipconfig /flushdns | Out-Null
Clear-DnsClientCache -ErrorAction SilentlyContinue
Write-Host "  DNS cache flushed"

Write-Step "[6/11] Resetting Windows SSL state and certificate URL cache..."
try {
    Start-Process rundll32.exe "InetCpl.cpl,ClearMyTracksByProcess 8" -Wait
    Write-Host "  Windows SSL state cleared"
}
catch {
    Write-Host "  SSL state clear failed: $($_.Exception.Message)" -ForegroundColor DarkYellow
}

try {
    certutil -urlcache * delete | Out-Null
    Write-Host "  Certificate URL cache cleared"
}
catch {
    Write-Host "  Certificate URL cache clear skipped" -ForegroundColor DarkYellow
}

Write-Step "[7/11] Clearing browser SSL/HSTS/cache data..."
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
            Get-ChildItem $Root -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -eq "Default" -or $_.Name -like "Profile *" } |
            ForEach-Object {
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
        Get-ChildItem $FirefoxLocal -Directory -ErrorAction SilentlyContinue |
        ForEach-Object {
            Remove-Item "$($_.FullName)\cache2\*" -Force -Recurse -ErrorAction SilentlyContinue
            Remove-Item "$($_.FullName)\startupCache\*" -Force -Recurse -ErrorAction SilentlyContinue
        }
    }

    $FirefoxRoaming = "$Base\AppData\Roaming\Mozilla\Firefox\Profiles"
    if (Test-Path $FirefoxRoaming) {
        Get-ChildItem $FirefoxRoaming -Directory -ErrorAction SilentlyContinue |
        ForEach-Object {
            Remove-Item "$($_.FullName)\SiteSecurityServiceState.txt" -Force -ErrorAction SilentlyContinue
        }
    }

    $OperaPaths = @(
        "$Base\AppData\Local\Opera Software\Opera Stable\Cache\*",
        "$Base\AppData\Local\Opera Software\Opera Stable\Code Cache\*",
        "$Base\AppData\Roaming\Opera Software\Opera Stable\TransportSecurity"
    )
    foreach ($Item in $OperaPaths) {
        Remove-Item $Item -Force -Recurse -ErrorAction SilentlyContinue
    }
}
Write-Host "  Browser SSL/HSTS/cache cleanup completed"

Write-Step "[8/11] Resetting network stack and WinHTTP proxy..."
netsh winsock reset | Out-Null
netsh int ip reset | Out-Null
netsh winhttp reset proxy | Out-Null
Write-Host "  Winsock reset completed"
Write-Host "  TCP/IP reset completed"
Write-Host "  WinHTTP proxy reset completed"

Write-Step "[9/11] Testing DNS for $TargetHost..."
try {
    $DNS = Resolve-DnsName $TargetHost -Server 8.8.8.8 -ErrorAction Stop
    Write-Host "DNS Resolution: OK" -ForegroundColor Green
    $DNS |
    Where-Object {$_.IPAddress} |
    Select-Object -ExpandProperty IPAddress -Unique |
    ForEach-Object { Write-Host "  IP: $_" }
}
catch {
    Write-Host "DNS Resolution: FAILED" -ForegroundColor Red
    Write-Host "  $($_.Exception.Message)" -ForegroundColor DarkYellow
}

Write-Step "[10/11] Testing TCP port $TargetPort for $TargetHost..."
try {
    $Conn = Test-NetConnection $TargetHost -Port $TargetPort -WarningAction SilentlyContinue
    if ($Conn.TcpTestSucceeded) {
        Write-Host "TCP Port $TargetPort: OK" -ForegroundColor Green
    }
    else {
        Write-Host "TCP Port $TargetPort: FAILED" -ForegroundColor Red
    }
}
catch {
    Write-Host "TCP Port Test Failed" -ForegroundColor Red
}

Write-Step "[11/11] Testing web request and opening target..."
try {
    $Response = Invoke-WebRequest -Uri $TargetUrl -UseBasicParsing -TimeoutSec 20 -ErrorAction Stop
    Write-Host "Web Request: OK, HTTP $($Response.StatusCode)" -ForegroundColor Green
}
catch {
    Write-Host "Web Request: FAILED" -ForegroundColor Red
    Write-Host "  $($_.Exception.Message)" -ForegroundColor DarkYellow
    Write-Host ""
    Write-Host "Note: If browser shows NET::ERR_CERT_COMMON_NAME_INVALID, the server certificate is wrong for this domain." -ForegroundColor Yellow
    Write-Host "A local reset cannot fix a wrong server-side SSL certificate." -ForegroundColor Yellow
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
