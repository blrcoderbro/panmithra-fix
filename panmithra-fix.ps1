# =====================================================================
# PANMITHRA QUICK FIX TOOL
# - Run as Administrator
# - Sets Google DNS (8.8.8.8 / 8.8.4.4) on all active adapters
# - Enables Secure DNS (DoH) in Chrome/Edge/Brave/Chromium
# - Enables DoH in Firefox
# - Flushes DNS cache
# - Clears SSL state
# - Resets Winsock/TCP/IP
# - Resets WinHTTP Proxy
# - Clears browser caches
# - Tests panmithra.com DNS + HTTPS
# - Opens login page
# =====================================================================

# Self-elevate
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)) {
    Start-Process powershell "-ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

Clear-Host

Write-Host ""
Write-Host "=== PANMITHRA CONNECTIVITY REPAIR TOOL ===" -ForegroundColor Green
Write-Host ""

# Close browsers
Write-Host "[1/9] Closing browsers..." -ForegroundColor Cyan
"chrome","msedge","firefox","brave","opera","iexplore" | ForEach-Object {
    Stop-Process -Name $_ -Force -ErrorAction SilentlyContinue
}

# Set DNS
Write-Host "[2/9] Setting Google DNS..." -ForegroundColor Cyan

Get-NetAdapter |
Where-Object { $_.Status -eq "Up" } |
ForEach-Object {
    try {
        Set-DnsClientServerAddress `
            -InterfaceIndex $_.InterfaceIndex `
            -ServerAddresses ("8.8.8.8","8.8.4.4") `
            -ErrorAction Stop

        Write-Host "  OK  $($_.Name)"
    }
    catch {}
}

# Chromium Secure DNS
Write-Host "[3/9] Enabling Secure DNS..." -ForegroundColor Cyan

$Policies = @(
    "HKLM:\SOFTWARE\Policies\Google\Chrome",
    "HKLM:\SOFTWARE\Policies\Microsoft\Edge",
    "HKLM:\SOFTWARE\Policies\BraveSoftware\Brave",
    "HKLM:\SOFTWARE\Policies\Chromium"
)

foreach ($Policy in $Policies) {

    New-Item $Policy -Force | Out-Null

    New-ItemProperty `
        -Path $Policy `
        -Name DnsOverHttpsMode `
        -Value secure `
        -PropertyType String `
        -Force | Out-Null

    New-ItemProperty `
        -Path $Policy `
        -Name DnsOverHttpsTemplates `
        -Value "https://dns.google/dns-query" `
        -PropertyType String `
        -Force | Out-Null
}

# Firefox DoH
Write-Host "[4/9] Configuring Firefox Secure DNS..." -ForegroundColor Cyan

$Users = Get-ChildItem C:\Users -Directory -ErrorAction SilentlyContinue |
Where-Object {
    $_.Name -notin @(
        "Public",
        "Default",
        "Default User",
        "All Users"
    )
}

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
Write-Host "[5/9] Flushing DNS cache..." -ForegroundColor Cyan
ipconfig /flushdns | Out-Null
Clear-DnsClientCache -ErrorAction SilentlyContinue

# SSL state
Write-Host "[6/9] Clearing SSL state..." -ForegroundColor Cyan
Start-Process rundll32.exe "InetCpl.cpl,ClearMyTracksByProcess 8" -Wait

# Network reset
Write-Host "[7/9] Resetting network stack..." -ForegroundColor Cyan
netsh winsock reset | Out-Null
netsh int ip reset | Out-Null
netsh winhttp reset proxy | Out-Null

# Clear caches
Write-Host "[8/9] Clearing browser caches..." -ForegroundColor Cyan

foreach ($User in $Users) {

    $Base = $User.FullName

    $Paths = @(
        "$Base\AppData\Local\Google\Chrome\User Data\Default\Cache",
        "$Base\AppData\Local\Google\Chrome\User Data\Default\Code Cache",
        "$Base\AppData\Local\Google\Chrome\User Data\Default\GPUCache",

        "$Base\AppData\Local\Microsoft\Edge\User Data\Default\Cache",
        "$Base\AppData\Local\Microsoft\Edge\User Data\Default\Code Cache",
        "$Base\AppData\Local\Microsoft\Edge\User Data\Default\GPUCache",

        "$Base\AppData\Local\BraveSoftware\Brave-Browser\User Data\Default\Cache",
        "$Base\AppData\Local\BraveSoftware\Brave-Browser\User Data\Default\Code Cache",
        "$Base\AppData\Local\BraveSoftware\Brave-Browser\User Data\Default\GPUCache",

        "$Base\AppData\Local\Mozilla\Firefox\Profiles\*\cache2",
        "$Base\AppData\Local\Opera Software\Opera Stable\Cache",
        "$Base\AppData\Local\Opera Software\Opera Stable\Code Cache"
    )

    foreach ($Path in $Paths) {
        Remove-Item "$Path\*" -Force -Recurse -ErrorAction SilentlyContinue
    }
}

# Test site
Write-Host "[9/9] Testing panmithra.com..." -ForegroundColor Cyan
Write-Host ""

try {

    $DNS = Resolve-DnsName panmithra.com -Server 8.8.8.8 -ErrorAction Stop

    Write-Host "DNS Resolution: OK" -ForegroundColor Green

    $DNS |
    Where-Object {$_.IPAddress} |
    Select-Object -ExpandProperty IPAddress |
    ForEach-Object {
        Write-Host "  IP: $_"
    }

}
catch {
    Write-Host "DNS Resolution: FAILED" -ForegroundColor Red
}

try {

    $Conn = Test-NetConnection panmithra.com -Port 443 -WarningAction SilentlyContinue

    if ($Conn.TcpTestSucceeded) {
        Write-Host "HTTPS Port 443: OK" -ForegroundColor Green
    }
    else {
        Write-Host "HTTPS Port 443: FAILED" -ForegroundColor Red
    }

}
catch {
    Write-Host "HTTPS Test Failed" -ForegroundColor Red
}

Write-Host ""
Write-Host "Opening Panmithra Login Page..." -ForegroundColor Cyan

Start-Process "https://panmithra.com/portallogin/login.php"

Write-Host ""
Write-Host "==================================================" -ForegroundColor Yellow
Write-Host "RESTART WINDOWS BEFORE TESTING AGAIN"
Write-Host ""
Write-Host "If you STILL get:"
Write-Host "NET::ERR_CERT_COMMON_NAME_INVALID"
Write-Host ""
Write-Host "The SSL certificate installed on the server"
Write-Host "does not match panmithra.com."
Write-Host "This must be fixed on the web server. Contact PANMITHRA Support"
Write-Host "==================================================" -ForegroundColor Yellow
Write-Host ""

pause