#requires -Version 7

$RequiredModules = @(
    'Microsoft.Graph.Users',
    'Microsoft.Graph.Groups'
)

foreach ($module in $RequiredModules) {
    Install-PSResource -Name $module -TrustRepository -WarningAction SilentlyContinue
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "IMPORTANT: Required Permissions" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "This script requires 'User Administrator' role or higher." -ForegroundColor Yellow
Write-Host "If you have PIM (Privileged Identity Management), activate the role before running." -ForegroundColor Yellow
Write-Host "`nActivate at: https://portal.azure.com/#view/Microsoft_Azure_PIMCommon/ActivationMenuBlade" -ForegroundColor Cyan
Write-Host ""

$continue = Read-Host "Have you activated the required role? (y/n)"
if ($continue -ne 'y') {
    Write-Host "Please activate the required role and run the script again." -ForegroundColor Yellow
    exit 0
}

# Connect with elevated permissions
Write-Host "`nConnecting to Microsoft Graph..." -ForegroundColor Cyan
Connect-MgGraph -Scopes "User.ReadWrite.All","Directory.ReadWrite.All","Group.ReadWrite.All" 

$context = Get-MgContext
Write-Host "Connected as: $($context.Account)" -ForegroundColor Green
Write-Host "Tenant: $($context.TenantId)" -ForegroundColor Green

# Delete lab users

# Variables
$UserNamePrefix = "LabUser-"
$UPNSuffix = '@' + ((Get-MgContext).Account -split "@")[1] # Get UPN suffix from the signed-in account (@xxx.onmicrosoft.com)

# Get all users matching the pattern
Write-Host "`nFetching users matching pattern: $UserNamePrefix*" -ForegroundColor Cyan
$Users = Get-MgUser -Filter "startsWith(DisplayName,'$UserNamePrefix')" -All | Where-Object UserPrincipalName -like "*$UPNSuffix" | Sort-Object DisplayName

if ($Users.Count -eq 0) {
    Write-Host "No users found matching pattern: $UserNamePrefix*" -ForegroundColor Yellow
    exit 0
}

Write-Host "`nFound $($Users.Count) user(s) to delete:" -ForegroundColor Green
$Users | ForEach-Object {
    Write-Host "  - $($_.UserPrincipalName) ($($_.DisplayName))" -ForegroundColor White
}

# Confirm deletion
$confirm = Read-Host "`nAre you sure you want to delete these users? This cannot be undone. Type 'DELETE' to confirm"
if ($confirm -ne 'DELETE') {
    Write-Host "Cancelled. No users were deleted." -ForegroundColor Yellow
    exit 0
}

# Delete users
$successCount = 0
$failCount = 0

foreach ($user in $Users) {
    Write-Host "Deleting user: $($user.UserPrincipalName)" -ForegroundColor Yellow
    
    try {
        Remove-MgUser -UserId $user.Id -Confirm:$false
        Write-Host "  ✓ Successfully deleted: $($user.UserPrincipalName)" -ForegroundColor Green
        $successCount++
    }
    catch {
        Write-Host "  ✗ Error deleting user $($user.UserPrincipalName): $_" -ForegroundColor Red
        $failCount++
    }
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "DELETION SUMMARY" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Total users processed: $($Users.Count)" -ForegroundColor White
Write-Host "  ✓ Successfully deleted: $successCount" -ForegroundColor Green
Write-Host "  ✗ Failed to delete: $failCount" -ForegroundColor Red

if ($successCount -gt 0) {
    Write-Host "`nNote: Deleted users are moved to 'Deleted users' and can be restored within 30 days." -ForegroundColor Yellow
    Write-Host "To permanently delete, go to Entra ID > Users > Deleted users in Azure Portal." -ForegroundColor Yellow
}
