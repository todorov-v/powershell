# Get script directory
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# Read parameters from params-ntnx.ini
$ParamsFile = "$ScriptDir\params-ntnx1.ini"

if (-Not (Test-Path $ParamsFile)) {
    Write-Host "Error: params-ntnx.ini not found!" -ForegroundColor Red
    exit
}

# Function to parse INI file
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

$Config = Parse-IniFile -FilePath $ParamsFile
$Nutanix = $Config["Nutanix"]

$ClusterIP = $Nutanix["NTNX_CLUSTER_IP"]
$Username = $Nutanix["NTNX_USERNAME"]
$Password = $Nutanix["NTNX_PASSWORD"]
$EnableCompression = $Nutanix["ENABLE_COMPRESSION"]
Write-Host "Using Nutanix IP: $ClusterIP"
# Ignore invalid vCenter SSL certificates
Set-PowerCLIConfiguration -Scope User -InvalidCertificateAction Ignore -Confirm:$false

# API Endpoints
$BaseURL = "https://" + $ClusterIP + ":9440/api/nutanix/v3"
Write-Host "Using Nutanix BaseURL: $BaseURL"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$StorageContainersURL = "$BaseURL/storage_containers"
Write-Host "Using Nutanix API URL: $StorageContainersURL"
# Ignore SSL Certificate Errors (self-signed certificates)
[System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
Write-Host "Using Nutanix User: $username"
# Authenticate with Nutanix API
$AuthString = "$Username`:$Password"  # Combine username and password with a colon
$Bytes = [System.Text.Encoding]::UTF8.GetBytes($AuthString)
$Base64Auth = [Convert]::ToBase64String($Bytes)
$AuthHeader = @{
    "Authorization" = "Basic " + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("$Username`:$Password"))
    "Content-Type"  = "application/json"
}
Write-Host "Using Nutanix Header: "Basic $Username`:$Password""
Invoke-RestMethod -Uri $BaseURL -Method Get -Headers $AuthHeader 
# Step 1: Get Storage Container ID
Write-Host "Searching for a container with name starting with 'default-container'..."

try {
    $StorageResponse = Invoke-RestMethod -Uri $StorageContainersURL -Method Get -Headers $AuthHeader
    $Datastore = $StorageResponse.entities | Where-Object { $_.status.name -like "default-container*" }

    if ($null -eq $Datastore) {
        Write-Host "No storage container found with name starting with 'default-container'!" -ForegroundColor Red
        exit
    }

    $DatastoreID = $Datastore.metadata.uuid
    $CurrentName = $Datastore.status.name
    Write-Host "Found Datastore: $CurrentName (ID: $DatastoreID)"
}
catch {
    Write-Host "Error retrieving storage containers: $_" -ForegroundColor Red
    exit
}

# Step 2: Rename Datastore if necessary
$NewDatastoreName = "default-container"

if ($CurrentName -ne $NewDatastoreName) {
    Write-Host "Renaming '$CurrentName' to '$NewDatastoreName'..."

    $RenameBody = @{
        "api_version" = "3.1"
        "metadata"    = @{
            "kind" = "storage_container"
            "uuid" = $DatastoreID
        }
        "spec"        = @{
            "name" = $NewDatastoreName
        }
    } | ConvertTo-Json -Depth 3

    try {
        Invoke-RestMethod -Uri "$StorageContainersURL/$DatastoreID" -Method Put -Headers $AuthHeader -Body $RenameBody -ContentType "application/json"
        Write-Host "Datastore renamed successfully!"
    }
    catch {
        Write-Host "Error renaming datastore: $_" -ForegroundColor Red
    }
}
else {
    Write-Host "Datastore already named 'default-container', no renaming needed."
}

# Step 3: Enable Compression (if required)
if ($EnableCompression -eq "True") {
    Write-Host "Enabling compression on '$NewDatastoreName'..."

    $CompressionBody = @{
        "api_version" = "3.1"
        "metadata"    = @{
            "kind" = "storage_container"
            "uuid" = $DatastoreID
        }
        "spec"        = @{
            "compression_enabled" = $true
        }
    } | ConvertTo-Json -Depth 3

    try {
        Invoke-RestMethod -Uri "$StorageContainersURL/$DatastoreID" -Method Put -Headers $AuthHeader -Body $CompressionBody -ContentType "application/json"
        Write-Host "Compression enabled on '$NewDatastoreName'."
    }
    catch {
        Write-Host "Error enabling compression: $_" -ForegroundColor Red
    }
}

Write-Host "Script execution complete!"
