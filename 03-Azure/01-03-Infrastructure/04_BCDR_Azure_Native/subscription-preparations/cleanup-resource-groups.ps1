# Cleanup script for BCDR resource groups
# Handles deletion of backup policies and instances before deleting resource groups

param(
    [string]$resourceGroupPattern = "labuser*",
    [switch]$WhatIf
)

# Get all resource groups matching the pattern
Write-Host "`nFetching resource groups matching pattern: $resourceGroupPattern" -ForegroundColor Cyan
$resourceGroups = az group list --query "[?starts_with(name, '$($resourceGroupPattern.Replace('*', ''))')].{Name:name}" -o json | ConvertFrom-Json

if ($resourceGroups.Count -eq 0) {
    Write-Host "No resource groups found matching pattern." -ForegroundColor Yellow
    exit 0
}

Write-Host "Found $($resourceGroups.Count) resource groups to delete:" -ForegroundColor Green
$resourceGroups | ForEach-Object { Write-Host "  - $($_.Name)" }

if ($WhatIf) {
    Write-Host "`n[WhatIf mode] No changes will be made." -ForegroundColor Yellow
    exit 0
}

$confirm = Read-Host "`nAre you sure you want to delete these resource groups? (yes/no)"
if ($confirm -ne 'yes') {
    Write-Host "Cancelled." -ForegroundColor Yellow
    exit 0
}

foreach ($rg in $resourceGroups) {
    $rgName = $rg.Name
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "Processing: $rgName" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    
    # Step 1: Find and delete backup instances in DataProtection Backup Vaults
    Write-Host "  [1/4] Checking for Backup Instances..." -ForegroundColor Yellow
    $backupVaults = az resource list --resource-group $rgName --resource-type "Microsoft.DataProtection/BackupVaults" --query "[].{Name:name}" -o json 2>$null | ConvertFrom-Json
    
    if ($backupVaults -and $backupVaults.Count -gt 0) {
        foreach ($vault in $backupVaults) {
            Write-Host "    Found Backup Vault: $($vault.Name)" -ForegroundColor White
            Write-Host "      Skipping backup instance listing (command hangs)" -ForegroundColor Yellow
            Write-Host "      Attempting to delete vault directly - this will fail if instances exist" -ForegroundColor Yellow
            
            # Skip listing and just try to delete the vault
            # If it fails due to instances, we'll handle it manually
            Write-Host "      Deleting backup vault..." -ForegroundColor Gray
            az resource delete --ids "/subscriptions/$((az account show --query id -o tsv))/resourceGroups/$rgName/providers/Microsoft.DataProtection/BackupVaults/$($vault.Name)" --no-wait 2>$null
            
            if ($LASTEXITCODE -ne 0) {
                Write-Host "      Warning: Vault deletion failed (likely has backup instances)" -ForegroundColor Yellow
                Write-Host "      You may need to manually delete backup instances via Azure Portal" -ForegroundColor Yellow
                Write-Host "      Portal: Home > Backup vaults > $($vault.Name) > Backup Instances" -ForegroundColor Cyan
            }
        }
    } else {
        Write-Host "    No Backup Vaults found" -ForegroundColor Gray
    }
    
    # Step 2: Find and delete items in Recovery Services Vaults
    Write-Host "  [2/4] Checking for Recovery Services Vaults..." -ForegroundColor Yellow
    $recoveryVaults = az resource list --resource-group $rgName --resource-type "Microsoft.RecoveryServices/vaults" --query "[].{Name:name}" -o json 2>$null | ConvertFrom-Json
    
    if ($recoveryVaults -and $recoveryVaults.Count -gt 0) {
        foreach ($vault in $recoveryVaults) {
            Write-Host "    Found Recovery Vault: $($vault.Name)" -ForegroundColor White
            
            # Disable soft delete
            Write-Host "      Disabling soft delete..." -ForegroundColor Gray
            az backup vault backup-properties set --name $vault.Name --resource-group $rgName --soft-delete-feature-state Disable 2>$null
            
            # Get protected items
            $protectedItems = az backup item list --vault-name $vault.Name --resource-group $rgName --query "[].{Name:name, ContainerName:properties.containerName}" -o json 2>$null | ConvertFrom-Json
            
            if ($protectedItems -and $protectedItems.Count -gt 0) {
                foreach ($item in $protectedItems) {
                    Write-Host "      Deleting protected item: $($item.Name)" -ForegroundColor Gray
                    az backup protection disable --vault-name $vault.Name --resource-group $rgName --container-name $item.ContainerName --item-name $item.Name --delete-backup-data true --yes 2>$null
                }
            }
            
            # Delete backup policies
            $backupPolicies = az backup policy list --vault-name $vault.Name --resource-group $rgName --query "[].{Name:name}" -o json 2>$null | ConvertFrom-Json
            
            if ($backupPolicies -and $backupPolicies.Count -gt 0) {
                foreach ($policy in $backupPolicies) {
                    if ($policy.Name -notlike "Default*") {
                        Write-Host "      Deleting backup policy: $($policy.Name)" -ForegroundColor Gray
                        az backup policy delete --vault-name $vault.Name --resource-group $rgName --name $policy.Name 2>$null
                    }
                }
            }
        }
    }
    
    # Step 3: Remove replication protected items
    Write-Host "  [3/4] Checking for Site Recovery replication..." -ForegroundColor Yellow
    if ($recoveryVaults -and $recoveryVaults.Count -gt 0) {
        foreach ($vault in $recoveryVaults) {
            $replicationFabrics = az resource list --resource-group $rgName --namespace Microsoft.RecoveryServices --resource-type vaults/replicationFabrics --query "[].{Name:name}" -o json 2>$null | ConvertFrom-Json
            
            if ($replicationFabrics -and $replicationFabrics.Count -gt 0) {
                Write-Host "    Removing Site Recovery replication items..." -ForegroundColor Gray
                # This requires the Az PowerShell module, so just note it
                Write-Host "    Note: Manual removal of Site Recovery items may be needed via Portal" -ForegroundColor Yellow
            }
        }
    }
    
    # Step 4: Delete the resource group
    Write-Host "  [4/4] Deleting resource group..." -ForegroundColor Yellow
    az group delete --name $rgName --yes --no-wait
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  ✓ Resource group deletion initiated" -ForegroundColor Green
    } else {
        Write-Host "  ✗ Failed to delete resource group" -ForegroundColor Red
    }
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Cleanup complete!" -ForegroundColor Green
Write-Host "Note: Resource group deletions are running in background." -ForegroundColor Cyan
Write-Host "Check Azure Portal for final status." -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
