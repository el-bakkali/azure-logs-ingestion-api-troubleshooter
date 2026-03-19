<#
.SYNOPSIS
    Creates a demo environment for the Azure Logs Ingestion API Troubleshooter Bruno collection.

.DESCRIPTION
    Deploys all Azure resources needed to test the Logs Ingestion API:
    - Resource group
    - Log Analytics workspace
    - Custom table (TestLogs_CL)
    - Data Collection Rule with stream declarations
    - Entra ID app registration with client secret
    - RBAC role assignments (Monitoring Metrics Publisher, Reader)

    At the end, prints all values needed for the Bruno environment configuration.

.PARAMETER Location
    Azure region for resource deployment. Default: westeurope

.PARAMETER ResourceGroupName
    Name of the resource group to create. Default: rg-ingestion-api-demo

.PARAMETER WorkspaceName
    Name of the Log Analytics workspace. Default: law-ingestion-demo

.PARAMETER AppName
    Display name for the Entra ID app registration. Default: LogIngestionDemo

.EXAMPLE
    .\Deploy-DemoEnvironment.ps1
    .\Deploy-DemoEnvironment.ps1 -Location eastus -ResourceGroupName rg-my-demo

.NOTES
    Prerequisites:
    - Azure CLI installed (https://learn.microsoft.com/en-us/cli/azure/install-azure-cli)
    - Logged in via 'az login'
    - Sufficient permissions to create resources and app registrations

    Cleanup:
    Run the cleanup command printed at the end to remove all resources.
#>

param(
    [string]$Location = "westeurope",
    [string]$ResourceGroupName = "rg-ingestion-api-demo",
    [string]$WorkspaceName = "law-ingestion-demo",
    [string]$AppName = "LogIngestionDemo"
)

$ErrorActionPreference = "Stop"

# ============================================================
# Validate prerequisites
# ============================================================

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " Azure Logs Ingestion API - Demo Environment Setup" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "Checking Azure CLI login status..." -ForegroundColor Gray
$account = az account show --query "{subscriptionId:id, tenantId:tenantId, name:name}" -o json 2>$null | ConvertFrom-Json
if (-not $account) {
    Write-Host "Not logged in. Run 'az login' first." -ForegroundColor Red
    exit 1
}

$SubscriptionId = $account.subscriptionId
$TenantId = $account.tenantId

Write-Host "Subscription: $($account.name)" -ForegroundColor Green
Write-Host "Subscription ID: $SubscriptionId" -ForegroundColor Gray
Write-Host "Tenant ID: $TenantId" -ForegroundColor Gray
Write-Host ""

# ============================================================
# Step 1: Create resource group
# ============================================================

Write-Host "[1/7] Creating resource group '$ResourceGroupName' in '$Location'..." -ForegroundColor Yellow
az group create --name $ResourceGroupName --location $Location -o none
Write-Host "       Done." -ForegroundColor Green

# ============================================================
# Step 2: Create Log Analytics workspace
# ============================================================

Write-Host "[2/7] Creating Log Analytics workspace '$WorkspaceName'..." -ForegroundColor Yellow
az monitor log-analytics workspace create `
    --resource-group $ResourceGroupName `
    --workspace-name $WorkspaceName `
    --location $Location `
    --retention-time 30 `
    -o none

$workspaceResourceId = (az monitor log-analytics workspace show `
    --resource-group $ResourceGroupName `
    --workspace-name $WorkspaceName `
    --query "id" -o tsv)

Write-Host "       Done." -ForegroundColor Green

# ============================================================
# Step 3: Create custom table
# ============================================================

Write-Host "[3/7] Creating custom table 'TestLogs_CL'..." -ForegroundColor Yellow

$tableBody = @{
    properties = @{
        schema = @{
            name = "TestLogs_CL"
            columns = @(
                @{ name = "TimeGenerated"; type = "datetime"; description = "Timestamp of the log event" }
                @{ name = "Computer";      type = "string";   description = "Source computer name" }
                @{ name = "Severity";      type = "string";   description = "Log severity level" }
                @{ name = "Message";       type = "string";   description = "Log message content" }
                @{ name = "RequestDuration"; type = "real";   description = "Duration in milliseconds" }
            )
        }
    }
} | ConvertTo-Json -Depth 10

$tableFile = Join-Path $env:TEMP "table-payload.json"
$tableBody | Out-File -FilePath $tableFile -Encoding utf8

az rest --method PUT `
    --url "https://management.azure.com${workspaceResourceId}/tables/TestLogs_CL?api-version=2022-10-01" `
    --body "@$tableFile" `
    --headers "Content-Type=application/json" `
    -o none

Remove-Item $tableFile -ErrorAction SilentlyContinue
Write-Host "       Done." -ForegroundColor Green

# ============================================================
# Step 4: Create Data Collection Rule
# ============================================================

Write-Host "[4/7] Creating Data Collection Rule 'dcr-testlogs-ingestion'..." -ForegroundColor Yellow

$dcrBody = @{
    location = $Location
    kind = "Direct"
    properties = @{
        streamDeclarations = @{
            "Custom-TestLogs" = @{
                columns = @(
                    @{ name = "Time";            type = "datetime" }
                    @{ name = "Computer";        type = "string" }
                    @{ name = "Severity";        type = "string" }
                    @{ name = "Message";         type = "string" }
                    @{ name = "RequestDuration"; type = "real" }
                )
            }
        }
        destinations = @{
            logAnalytics = @(
                @{
                    workspaceResourceId = $workspaceResourceId
                    name = "workspace"
                }
            )
        }
        dataFlows = @(
            @{
                streams = @("Custom-TestLogs")
                destinations = @("workspace")
                transformKql = "source | extend TimeGenerated = Time | project-away Time"
                outputStream = "Custom-TestLogs_CL"
            }
        )
    }
} | ConvertTo-Json -Depth 10

$dcrFile = Join-Path $env:TEMP "dcr-payload.json"
$dcrBody | Out-File -FilePath $dcrFile -Encoding utf8

$dcrResult = az rest --method PUT `
    --url "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Insights/dataCollectionRules/dcr-testlogs-ingestion?api-version=2023-03-11" `
    --body "@$dcrFile" `
    --headers "Content-Type=application/json" `
    -o json | ConvertFrom-Json

$dcrImmutableId = $dcrResult.properties.immutableId
$ingestionEndpoint = $dcrResult.properties.endpoints.logsIngestion

Remove-Item $dcrFile -ErrorAction SilentlyContinue
Write-Host "       Done." -ForegroundColor Green

# ============================================================
# Step 5: Create Entra ID app registration
# ============================================================

Write-Host "[5/7] Creating app registration '$AppName'..." -ForegroundColor Yellow

$appResult = az ad app create --display-name $AppName --query "{appId:appId, objectId:id}" -o json | ConvertFrom-Json
$clientId = $appResult.appId

az ad sp create --id $clientId -o none 2>$null
$spId = (az ad sp show --id $clientId --query "id" -o tsv)

$secretResult = az ad app credential reset `
    --id $clientId `
    --display-name "demo-secret" `
    --years 1 `
    --query "password" -o tsv

$clientSecret = $secretResult

Write-Host "       Done." -ForegroundColor Green

# ============================================================
# Step 6: Assign RBAC roles
# ============================================================

Write-Host "[6/7] Assigning RBAC roles..." -ForegroundColor Yellow

$dcrResourceId = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Insights/dataCollectionRules/dcr-testlogs-ingestion"

# Monitoring Metrics Publisher on DCR (required for ingestion)
az role assignment create `
    --assignee $spId `
    --role "Monitoring Metrics Publisher" `
    --scope $dcrResourceId `
    -o none 2>$null

# Reader on resource group (required for DCR and table inspection)
az role assignment create `
    --assignee $spId `
    --role "Reader" `
    --scope "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName" `
    -o none 2>$null

Write-Host "       Done." -ForegroundColor Green

# ============================================================
# Step 7: Output Bruno environment values
# ============================================================

Write-Host "[7/7] Setup complete." -ForegroundColor Yellow
Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " Bruno Environment Values" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Copy these into Bruno > Environments > Azure:" -ForegroundColor Gray
Write-Host ""
Write-Host "  tenantId            $TenantId" -ForegroundColor White
Write-Host "  clientId            $clientId" -ForegroundColor White
Write-Host "  clientSecret        $clientSecret" -ForegroundColor White
Write-Host "  subscriptionId      $SubscriptionId" -ForegroundColor White
Write-Host "  resourceGroup       $ResourceGroupName" -ForegroundColor White
Write-Host "  workspaceName       $WorkspaceName" -ForegroundColor White
Write-Host "  dcrImmutableId      $dcrImmutableId" -ForegroundColor White
Write-Host "  ingestionEndpoint   $ingestionEndpoint" -ForegroundColor White
Write-Host "  streamName          Custom-TestLogs" -ForegroundColor White
Write-Host "  tableName           TestLogs_CL" -ForegroundColor White
Write-Host "  armBaseUrl          https://management.azure.com" -ForegroundColor White
Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " DCR Stream Schema (what the API expects)" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Time              datetime    (mapped to TimeGenerated by transform)" -ForegroundColor White
Write-Host "  Computer          string" -ForegroundColor White
Write-Host "  Severity          string" -ForegroundColor White
Write-Host "  Message           string" -ForegroundColor White
Write-Host "  RequestDuration   real" -ForegroundColor White
Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " Sample Payload (correct)" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host '  [' -ForegroundColor White
Write-Host '    {' -ForegroundColor White
Write-Host '      "Time": "2026-01-01T00:00:00Z",' -ForegroundColor White
Write-Host '      "Computer": "TestPC-1",' -ForegroundColor White
Write-Host '      "Severity": "Warning",' -ForegroundColor White
Write-Host '      "Message": "Disk space low",' -ForegroundColor White
Write-Host '      "RequestDuration": 125.5' -ForegroundColor White
Write-Host '    }' -ForegroundColor White
Write-Host '  ]' -ForegroundColor White
Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " Important Notes" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  - RBAC roles can take up to 30 minutes to propagate." -ForegroundColor Gray
Write-Host "  - First-time ingestion to a new table can take 10-15 minutes." -ForegroundColor Gray
Write-Host "  - The client secret expires in 1 year." -ForegroundColor Gray
Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " Cleanup Command" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  az group delete --name $ResourceGroupName --yes --no-wait" -ForegroundColor Yellow
Write-Host "  az ad app delete --id $clientId" -ForegroundColor Yellow
Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
