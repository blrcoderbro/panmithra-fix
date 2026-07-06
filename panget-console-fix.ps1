# =====================================================================
# PANGET CONSOLE CONNECTIVITY + SSL RESET TOOL
# Target: https://console.panget.in
# - Run as Administrator
# - Closes browsers
# - Sets Google DNS on active adapters
# - Enables Secure DNS / DoH in Chromium browsers and Firefox
# - Flushes DNS cache
# - Clears Windows SSL state
# - Clears certificate URL cache
# - Clears browser SSL/HSTS/cache data for the target
# - Resets Winsock/TCP/IP and WinHTTP proxy
# - Tests DNS + HTTPS for console.panget.in
# - Opens console.panget.in
# =====================================================================

$TargetHost = "console.panget.in"
$TargetUrl  = "https://console.panget.in"

# Self-elevate
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)) {
    Start-Process powershell "-ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

Clear-Host

Write-Host ""
Write-Host "=== PANGET CONSOLE CONNECTIVITY + SSL RESET TOOL ===" -ForegroundColor Green
Write-Host "Target: $TargetUrl" -ForegroundColor Yellow
Write-Host ""

# Build user list once
$Users = Get-ChildItem C:\Users -Directory -ErrorAction SilentlyContinue |
Where-Object {
    $_.Name -notin @("Public", "Default", "Default User", "All Users")
}

# Close browsers
Write-Host "[1/10] Closing browsers..." -ForegroundColor Cyan
"chrome","msedge","firefox","brave","opera","iexplore" | ForEach-Object {
    Stop-Process -Name $_ -Force -ErrorAction SilentlyContinue
}
Start-Sleep -Seconds 2

# Set DNS
Write-Host "[2/10] Setting Google DNS on active adapters..." -ForegroundColor Cyan
Get-NetAdapter -ErrorAction SilentlyContinue |
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

# Chromium Secure DNS
Write-Host "[3/10] Enabling Secure DNS / DoH for Chromium browsers..." -ForegroundColor Cyan
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

# Firefox DoH
Write-Host "[4/10] Configuring Firefox Secure DNS..." -ForegroundColor Cyan
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

# Flush DNS
Write-Host "[5/10] Flushing DNS cache..." -ForegroundColor Cyan
ipconfig /flushdns | Out-Null
Clear-DnsClientCache -ErrorAction SilentlyContinue

# SSL state reset
Write-Host "[6/10] Resetting Windows SSL state and certificate URL cache..." -ForegroundColor Cyan
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

# Browser SSL/HSTS/cache reset
Write-Host "[7/10] Clearing browser SSL/HSTS/cache data..." -ForegroundColor Cyan
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

# Network reset
Write-Host "[8/10] Resetting network stack and WinHTTP proxy..." -ForegroundColor Cyan
netsh winsock reset | Out-Null
netsh int ip reset | Out-Null
netsh winhttp reset proxy | Out-Null

# Test site
Write-Host "[9/10] Testing DNS and HTTPS for $TargetHost..." -ForegroundColor Cyan
Write-Host ""

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

try {
    $Conn = Test-NetConnection $TargetHost -Port 443 -WarningAction SilentlyContinue
    if ($Conn.TcpTestSucceeded) {
        Write-Host "HTTPS Port 443: OK" -ForegroundColor Green
    }
    else {
        Write-Host "HTTPS Port 443: FAILED" -ForegroundColor Red
    }
}
catch {
    Write-Host "HTTPS Port 443 Test Failed" -ForegroundColor Red
}

try {
    $Response = Invoke-WebRequest -Uri $TargetUrl -UseBasicParsing -TimeoutSec 20 -ErrorAction Stop
    Write-Host "SSL / HTTPS Certificate Validation: OK" -ForegroundColor Green
    Write-Host "HTTP Status: $($Response.StatusCode)"
}
catch {
    Write-Host "SSL / HTTPS Certificate Validation: FAILED" -ForegroundColor Red
    Write-Host "  $($_.Exception.Message)" -ForegroundColor DarkYellow
}

# Open site
Write-Host ""
Write-Host "[10/10] Opening $TargetUrl ..." -ForegroundColor Cyan
Start-Process $TargetUrl

Write-Host ""
Write-Host "==================================================" -ForegroundColor Yellow
Write-Host "DONE. RESTART WINDOWS BEFORE TESTING AGAIN."
Write-Host ""
Write-Host "If you still get NET::ERR_CERT_COMMON_NAME_INVALID,"
Write-Host "then the SSL certificate installed on the SERVER does"
Write-Host "not match $TargetHost. That cannot be fixed from Windows;"
Write-Host "the hosting/server SSL certificate must be reissued/installed."
Write-Host "==================================================" -ForegroundColor Yellow
Write-Host ""

pause
