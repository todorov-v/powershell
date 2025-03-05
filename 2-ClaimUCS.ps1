# Get script directory
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# Read parameters from params.txt
$ParamsFile = "$ScriptDir\params.txt"

if (-Not (Test-Path $ParamsFile)) {
    Write-Host "Error: params.txt not found!" -ForegroundColor Red
    exit
}

# Read all lines from params.txt
$ParamsLines = Get-Content $ParamsFile
$Devices = @()
$CurrentDevice = @{}

# Parse params.txt
foreach ($Line in $ParamsLines) {
    # Skip empty lines and comments
    if ($Line -match "^\s*$" -or $Line -match "^#") { 
        if ($CurrentDevice.Count -gt 0) {
            $Devices += ,$CurrentDevice
            $CurrentDevice = @{}
        }
        continue
    }
    
    # Parse key-value pairs
    if ($Line -match "^(.*?)=(.*)$") {
        $CurrentDevice[$matches[1].Trim()] = $matches[2].Trim()
    }
}

# Add last parsed device
if ($CurrentDevice.Count -gt 0) {
    $Devices += ,$CurrentDevice
}

# Function to claim a single device
function Claim-Device {
    param (
        [string]$CimcIP,
        [string]$CimcUsername,
        [string]$CimcPassword,
        [string]$IntersightApiKey
    )

    Write-Host "🚀 Processing CIMC: $CimcIP"

    # Cisco CIMC API URLs
    $CimcLoginUrl = "https://$CimcIP/api/aaaLogin.json"
    $CimcDeviceInfoUrl = "https://$CimcIP/api/class/ComputeBoard.json"
    $IntersightURL = "https://intersight.com/api/v1/asset/DeviceRegistrations"

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

    # Step 2: Retrieve Device ID and Claim Code
    $CimcHeaders = @{
        "Cookie" = "APIC-cookie=$CimcToken"
    }

    try {
        $CimcDeviceResponse = Invoke-RestMethod -Uri $CimcDeviceInfoUrl -Method Get -Headers $CimcHeaders
        $DeviceID = $CimcDeviceResponse.imdata[0].ComputeBoard.attributes.serial
        $ClaimCode = $CimcDeviceResponse.imdata[0].ComputeBoard.attributes.ClaimCode
        Write-Host "📌 Device ID: $DeviceID for CIMC ($CimcIP)"
        Write-Host "📌 Claim Code: $ClaimCode for CIMC ($CimcIP)"
    }
    catch {
        Write-Host "❌ Error retrieving device information from CIMC ($CimcIP): $_" -ForegroundColor Red
        return
    }

    # Step 3: Claim the device in Intersight
    $IntersightHeaders = @{
        "Accept"        = "application/json"
        "Content-Type"  = "application/json"
        "Authorization" = "Bearer $IntersightApiKey"
    }

    $IntersightBody = @{
        "DeviceID"  = $DeviceID
        "ClaimCode" = $ClaimCode
    } | ConvertTo-Json -Depth 2

    try {
        $IntersightResponse = Invoke-RestMethod -Uri $IntersightURL -Method Post -Headers $IntersightHeaders -Body $IntersightBody
        Write-Host "✅ Device successfully claimed in Intersight for CIMC ($CimcIP)!"
    }
    catch {
        Write-Host "❌ Error claiming device in Intersight for CIMC ($CimcIP): $_" -ForegroundColor Red
    }
}

# Run claims in parallel
$Jobs = @()

foreach ($Device in $Devices) {
    if ($Device.ContainsKey("CIMC_IP") -and $Device.ContainsKey("CIMC_USERNAME") -and $Device.ContainsKey("CIMC_PASSWORD") -and $Device.ContainsKey("INTERSIGHT_API_KEY")) {
        $Jobs += Start-Job -ScriptBlock {
            param ($CimcIP, $CimcUsername, $CimcPassword, $IntersightApiKey)

            # Import function inside the job
            . $using:Claim-Device

            # Call function with parameters
            Claim-Device -CimcIP $CimcIP -CimcUsername $CimcUsername -CimcPassword $CimcPassword -IntersightApiKey $IntersightApiKey
        } -ArgumentList $Device["CIMC_IP"], $Device["CIMC_USERNAME"], $Device["CIMC_PASSWORD"], $Device["INTERSIGHT_API_KEY"]
    }
}

# Wait for all jobs to complete
Write-Host "⏳ Waiting for all claims to finish..."
$Jobs | ForEach-Object { Receive-Job -Job $_ -Wait }
Write-Host "✅ All devices processed!"
