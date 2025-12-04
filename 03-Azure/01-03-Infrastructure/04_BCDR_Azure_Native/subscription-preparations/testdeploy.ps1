# Azure BCDR Multi-User Deployment Script
# Deploys the same ARM template multiple times with different user prefixes (labuser1, labuser2, etc.)

# Check current Azure CLI login
Write-Host "`nChecking current Azure CLI login..." -ForegroundColor Cyan
$currentAccount = az account show 2>$null | ConvertFrom-Json

if ($null -eq $currentAccount) {
    Write-Host "Not logged in to Azure CLI." -ForegroundColor Yellow
} else {
    Write-Host "Currently logged in as: $($currentAccount.user.name)" -ForegroundColor Green
    $continue = Read-Host "Is this the correct account? (y/n)"
    if ($continue -ne 'y') {
        Write-Host "`nLogging out current account..." -ForegroundColor Cyan
        az logout
    } else {
        # Skip re-login
        $skipLogin = $true
    }
}

# Always offer to login if not skipped
if (-not $skipLogin) {
    Write-Host "`nPlease login with the correct Azure account..." -ForegroundColor Cyan
    az login
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Login failed. Exiting." -ForegroundColor Red
        exit 1
    }
    
    # Show who is now logged in
    $currentAccount = az account show | ConvertFrom-Json
    Write-Host "`nNow logged in as: $($currentAccount.user.name)" -ForegroundColor Green
}

# List available subscriptions
Write-Host "`nFetching available subscriptions for logged-in account..." -ForegroundColor Cyan
$subscriptions = az account list --query "[].{Name:name, SubscriptionId:id, State:state}" -o json | ConvertFrom-Json

if ($subscriptions.Count -eq 0) {
    Write-Host "No subscriptions found for the current account." -ForegroundColor Red
    exit 1
}

Write-Host "`nAvailable Subscriptions:" -ForegroundColor Green
for ($i = 0; $i -lt $subscriptions.Count; $i++) {
    $sub = $subscriptions[$i]
    Write-Host "  [$($i + 1)] $($sub.Name) ($($sub.SubscriptionId)) - $($sub.State)"
}

# Prompt for subscription selection
$selection = Read-Host "`nSelect subscription number (1-$($subscriptions.Count))"
$selectedIndex = [int]$selection - 1

if ($selectedIndex -lt 0 -or $selectedIndex -ge $subscriptions.Count) {
    Write-Host "Invalid selection. Exiting." -ForegroundColor Red
    exit 1
}

$subscriptionId = $subscriptions[$selectedIndex].SubscriptionId
$subscriptionName = $subscriptions[$selectedIndex].Name

# Set the subscription
Write-Host "`nSetting subscription to: $subscriptionName ($subscriptionId)" -ForegroundColor Cyan
az account set --subscription $subscriptionId

if ($LASTEXITCODE -ne 0) {
    Write-Host "Failed to set subscription. Exiting." -ForegroundColor Red
    exit 1
}

# Prompt for deployment inputs
$deploymentCount = Read-Host "`nEnter number of deployments (e.g., 20)"
$vmAdminPassword = Read-Host "Enter VM admin password"

# File paths
$templateFile = "C:\GithubRepos\MicroHack-2025\MicroHack-main\03-Azure\01-03-Infrastructure\04_BCDR_Azure_Native\Infra\App1\deploy.json"
$parameterFile = "C:\GithubRepos\MicroHack-2025\MicroHack-main\03-Azure\01-03-Infrastructure\04_BCDR_Azure_Native\Infra\App1\main.parameters.json"
$location = "francecentral"

Write-Host "`nStarting $deploymentCount deployments..." -ForegroundColor Green

for ($i = 1; $i -le $deploymentCount; $i++) {
    $userPrefix = "labuser$i"
    $deploymentName = "bcdr-$userPrefix-$(Get-Date -Format 'yyyyMMddHHmmss')"
    
    Write-Host "`n[$i/$deploymentCount] Deploying for $userPrefix..." -ForegroundColor Yellow
    
    # Check if we need to re-authenticate (every 10 deployments or on error)
    if ($i % 10 -eq 0 -or $needReauth) {
        Write-Host "  Verifying authentication..." -ForegroundColor Gray
        $accountCheck = az account show 2>&1
        if ($LASTEXITCODE -ne 0 -or $accountCheck -like "*AADSTS*" -or $accountCheck -like "*refresh token*") {
            Write-Host "  Session expired. Re-authenticating..." -ForegroundColor Yellow
            az login --use-device-code
            if ($LASTEXITCODE -ne 0) {
                Write-Host "  Re-authentication failed. Stopping deployments." -ForegroundColor Red
                exit 1
            }
            az account set --subscription $subscriptionId
            $needReauth = $false
            Write-Host "  ✓ Re-authenticated successfully" -ForegroundColor Green
        }
    }
    
    # Deploy using Azure CLI with parameter overrides
    $deployOutput = az deployment sub create `
        --name $deploymentName `
        --location $location `
        --template-file $templateFile `
        --parameters $parameterFile `
        --parameters parDeploymentPrefix=$userPrefix vmAdminPassword=$vmAdminPassword `
        --no-wait 2>&1
    
    # Check if authentication failed
    if ($deployOutput -like "*AADSTS*" -or $deployOutput -like "*refresh token*") {
        Write-Host "  Authentication expired, will re-authenticate on next deployment" -ForegroundColor Yellow
        $needReauth = $true
        $i-- # Retry this deployment
        continue
    }
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  ✓ Deployment $i started successfully" -ForegroundColor Green
    } else {
        Write-Host "  ✗ Deployment $i failed to start" -ForegroundColor Red
        Write-Host "  Error: $deployOutput" -ForegroundColor Red
    }
}

Write-Host "`nAll $deploymentCount deployments initiated!" -ForegroundColor Green
Write-Host "Note: Deployments are running in background (--no-wait). Check Azure Portal for status." -ForegroundColor Cyan
