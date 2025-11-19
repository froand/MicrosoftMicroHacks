$subscriptions = Get-AzSubscription

# List of resource providers to register
$providers = @(
    "Microsoft.Compute",
    "Microsoft.Network",
    "Microsoft.Storage",
    "Microsoft.RecoveryServices",
    "Microsoft.Insights",
    "Microsoft.Authorization",
    "Microsoft.Resources",
    "Microsoft.ManagedIdentity",
    "Microsoft.KeyVault"
)

foreach ($subscription in $subscriptions) {
    Set-AzContext -SubscriptionId $subscription.Id
    foreach ($provider in $providers) {
        $rp = Get-AzResourceProvider -ProviderNamespace $provider
        if ($rp.RegistrationState -ne "Registered") {
            Write-Host "Registering $provider in subscription $($subscription.Name)..."
            Register-AzResourceProvider -ProviderNamespace $provider
        } else {
            Write-Host "$provider already registered in $($subscription.Name)"
        }
    }
}