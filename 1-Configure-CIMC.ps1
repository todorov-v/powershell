# Get script directory
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# Read parameters from CIMC-params.ini
$ParamsFile = "$ScriptDir\CIMC-params.ini"

if (-Not (Test-Path $ParamsFile)) {
    Write-Host "Error: CIMC-params.ini not found!" -ForegroundColor Red
    exit
}

# Read and parse INI file
function Parse-IniFile {
    param ([string]$FilePath)
    $Ini = @{}
    $CurrentSection = $null

    Get-Content $FilePath | ForEach-Object {
        $Line = $_.Trim()
        
        if ($Line -match "^\[(.+)\]$") {
            $CurrentSection = $matches[1]
            $Ini[$CurrentSection] = @{}
        }
        elseif ($Line -match "^(.*?)=(.*)$" -and $CurrentSection) {
            $Ini[$CurrentSection][$matches[1].Trim()] = $matches[2].Trim()
        }
    }
    
    return $Ini
}

$Devices = Parse-IniFile -FilePath $ParamsFile

# Function to configure DNS, SNMP, and NTP on CIMC
function Configure-CIMC {
    param (
        [string]$CimcIP,
        [string]$CimcUsername,
        [string]$CimcPassword,
        [string]$DNS1,
        [string]$DNS2,
        [string]$DNS3,
        [string]$SNMPCommunity,
        [string]$SNMPTarget,
        [string]$NTPServer
    )

    Write-Host "🚀 Configuring CIMC: $CimcIP"

    # Cisco CIMC API URLs
    $CimcLoginUrl = "https://$CimcIP/api/aaaLogin.json"
    $CimcDNSUrl = "https://$CimcIP/api/mo/sys/dns-svc.json"
    $CimcSNMPUrl = "https://$CimcIP/api/mo/sys/snmp-svc.json"
    $CimcNTPUrl = "https://$CimcIP/api/mo/sys/ntp-svc.json"

    # Ignore SSL Certificate Errors (if CIMC uses self-signed cert)
    [System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }

    # Step 1: Authenticate with CIMC
    $CimcAuthBody = @{
        aaaUser = @{
            name = $CimcUsername
            pwd  = $CimcPassword
        }
    } | ConvertTo-Json -Depth 2

    try {
        $CimcAuthResponse = Invoke-RestMethod -Uri $CimcLoginUrl -Method Post -Body $CimcAuthBody -ContentType "application/json"
        $CimcToken = $CimcAuthResponse.imdata.aaaLogin.attributes.token
        Write-Host "✅ Successfully authenticated with CIMC ($CimcIP)"
    }
    catch {
        Write-Host "❌ Error logging into CIMC ($CimcIP): $_" -ForegroundColor Red
        return
    }

    $CimcHeaders = @{
        "Cookie" = "APIC-cookie=$CimcToken"
    }

    # Step 2: Configure DNS
    $CimcDNSBody = @{
        dnsSettings = @{
            nameServers = @($DNS1, $DNS2, $DNS3)
        }
    } | ConvertTo-Json -Depth 2

    try {
        Invoke-RestMethod -Uri $CimcDNSUrl -Method Post -Headers $CimcHeaders -Body $CimcDNSBody -ContentType "application/json"
        Write-Host "✅ DNS configured for CIMC ($CimcIP): $DNS1, $DNS2, $DNS3"
    }
    catch {
        Write-Host "❌ Error configuring DNS for CIMC ($CimcIP): $_" -ForegroundColor Red
    }

    # Step 3: Configure SNMP
    $CimcSNMPBody = @{
        snmpSettings = @{
            communityString = $SNMPCommunity
            trapReceivers   = @(@{ ipAddress = $SNMPTarget })
        }
    } | ConvertTo-Json -Depth 2

    try {
        Invoke-RestMethod -Uri $CimcSNMPUrl -Method Post -Headers $CimcHeaders -Body $CimcSNMPBody -ContentType "application/json"
        Write-Host "✅ SNMP configured for CIMC ($CimcIP) -> Community: $SNMPCommunity, Target: $SNMPTarget"
    }
    catch {
        Write-Host "❌ Error configuring SNMP for CIMC ($CimcIP): $_" -ForegroundColor Red
    }

    # Step 4: Configure NTP
    $CimcNTPBody = @{
        ntpSettings = @{
            servers = @($NTPServer)
        }
    } | ConvertTo-Json -Depth 2

    try {
        Invoke-RestMethod -Uri $CimcNTPUrl -Method Post -Headers $CimcHeaders -Body $CimcNTPBody -ContentType "application/json"
        Write-Host "✅ NTP configured for CIMC ($CimcIP): $NTPServer"
    }
    catch {
        Write-Host "❌ Error configuring NTP for CIMC ($CimcIP): $_" -ForegroundColor Red
    }
}

# Run configurations in parallel
$Jobs = @()

foreach ($DeviceKey in $Devices.Keys) {
    $Device = $Devices[$DeviceKey]
    
    if ($Device.ContainsKey("CIMC_IP")) {
        $Jobs += Start-Job -ScriptBlock {
            param ($CimcIP, $CimcUsername, $CimcPassword, $DNS1, $DNS2, $DNS3, $SNMPCommunity, $SNMPTarget, $NTPServer)

            # Import function inside the job
            . $using:Configure-CIMC

            # Call function with parameters
            Configure-CIMC -CimcIP $CimcIP -CimcUsername $CimcUsername -CimcPassword $CimcPassword -DNS1 $DNS1 -DNS2 $DNS2 -DNS3 $DNS3 -SNMPCommunity $SNMPCommunity -SNMPTarget $SNMPTarget -NTPServer $NTPServer
        } -ArgumentList $Device["CIMC_IP"], $Device["CIMC_USERNAME"], $Device["CIMC_PASSWORD"], $Device["DNS1"], $Device["DNS2"], $Device["DNS3"], $Device["SNMP_COMMUNITY"], $Device["SNMP_TARGET"], $Device["NTP_SERVER"]
    }
}

Write-Host "⏳ Waiting for all configurations to finish..."
$Jobs | ForEach-Object { Receive-Job -Job $_ -Wait }
Write-Host "✅ All devices configured!"
