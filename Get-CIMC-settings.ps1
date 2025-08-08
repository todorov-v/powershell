# Function to create Redfish session
function Create-RedfishSession {
    param (
        [string]$CIMC_IP,
        [string]$CIMC_USERNAME,
        [string]$CIMC_PASSWORD
    )

    try {
        # Bypass SSL Certificate validation for non-SSL sites or self-signed certificates
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
        [System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}
        
        $uri = "https://$CIMC_IP/redfish/v1/SessionService/Sessions"

        # Redfish expects a JSON body with username and password
        $body = @{
            "UserName" = $CIMC_USERNAME
            "Password" = $CIMC_PASSWORD
        }

        # Headers for Redfish API
        $headers = @{
            "Content-Type" = "application/json"
        }

        # Send POST request to Redfish API to create session
        $response = Invoke-RestMethod -Uri $uri -Method Post -Body ($body | ConvertTo-Json) -Headers $headers -ErrorAction Stop
        return $response.SessionID
    } catch {
        # Use ${} for variable references in error handling
        Write-Host "[ERROR] Failed to create Redfish session for $CIMC_IP: $($error[0].Exception.Message)"
        return $null
    }
}

# Function to collect CIMC settings (DNS, SNMP, NTP) from Redfish
function Get-CIMCSettings {
    param (
        [string]$CIMC_IP,
        [string]$CIMC_USERNAME,
        [string]$CIMC_PASSWORD
    )

    try {
        # Create the Redfish session
        $sessionToken = Create-RedfishSession -CIMC_IP $CIMC_IP -CIMC_USERNAME $CIMC_USERNAME -CIMC_PASSWORD $CIMC_PASSWORD
        if ($sessionToken -eq $null) {
            Write-Host "[ERROR] Failed to create session for $CIMC_IP"
            return
        }

        # Collect DNS settings
        $dnsURI = "https://$CIMC_IP/redfish/v1/Managers/CIMC/DNS"
        $dnsResponse = Invoke-RestMethod -Uri $dnsURI -Headers @{ "X-Auth-Token" = $sessionToken } -Method Get
        $dnsSettings = $dnsResponse

        # Collect SNMP settings
        $snmpURI = "https://$CIMC_IP/redfish/v1/Managers/CIMC/SNMP"
        $snmpResponse = Invoke-RestMethod -Uri $snmpURI -Headers @{ "X-Auth-Token" = $sessionToken } -Method Get
        $snmpSettings = $snmpResponse

        # Collect NTP settings
        $ntpURI = "https://$CIMC_IP/redfish/v1/Managers/CIMC/NTP"
        $ntpResponse = Invoke-RestMethod -Uri $ntpURI -Headers @{ "X-Auth-Token" = $sessionToken } -Method Get
        $ntpSettings = $ntpResponse

        # Collect all settings into a hash table
        $collectedSettings = @{
            CIMC_IP     = $CIMC_IP
            DNS         = $dnsSettings
            SNMP        = $snmpSettings
            NTP         = $ntpSettings
        }

        # Save collected data to an INI-style file
        $iniContent = "[CIMC]`n"
        $iniContent += "CIMC_IP=$($CIMC_IP)`n"
        $iniContent += "DNS=$($dnsSettings.DNS1),$($dnsSettings.DNS2)`n"
        $iniContent += "SNMP_Enabled=$($snmpSettings.Enabled)`n"
        $iniContent += "SNMP_Community=$($snmpSettings.Community)`n"
        $iniContent += "NTP_Enabled=$($ntpSettings.Enabled)`n"
        $iniContent += "NTP_Server=$($ntpSettings.NTPServer)`n"

        # Write to a file (ensure the path is correct for your environment)
        $outputPath = "CIMC-Settings.ini"
        $iniContent | Out-File -FilePath $outputPath -Force

        Write-Host "[SUCCESS] Collected data saved to $outputPath"
    } catch {
        # Use ${} for variable references in error handling
        Write-Host "[ERROR] Failed to retrieve settings for $CIMC_IP: $($error[0].Exception.Message)"
    }
}

# Read parameters from a file (params-cimc.ini)
$iniFilePath = "params-cimc.ini"
if (Test-Path $iniFilePath) {
    $iniContent = Get-Content -Path $iniFilePath
    foreach ($line in $iniContent) {
        if ($line -match "CIMC_IP=(.*)") {
            $CIMC_IP = $matches[1].Trim()
        }
        if ($line -match "CIMC_USERNAME=(.*)") {
            $CIMC_USERNAME = $matches[1].Trim()
        }
        if ($line -match "CIMC_PASSWORD=(.*)") {
            $CIMC_PASSWORD = $matches[1].Trim()
        }

        if ($CIMC_IP -and $CIMC_USERNAME -and $CIMC_PASSWORD) {
            # Call the function to collect settings for the given CIMC
            Write-Host "Processing CIMC: $CIMC_IP..."
            Get-CIMCSettings -CIMC_IP $CIMC_IP -CIMC_USERNAME $CIMC_USERNAME -CIMC_PASSWORD $CIMC_PASSWORD
        }
    }
} else {
    Write-Host "[ERROR] Configuration file ($iniFilePath) not found."
}
