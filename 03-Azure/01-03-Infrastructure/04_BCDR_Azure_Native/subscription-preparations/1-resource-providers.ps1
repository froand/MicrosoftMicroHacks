# Get all subscriptions
#Connect-AzAccount -Tenant "9c0734c7-c4ff-4cab-b3d0-b4c4160937e7" -Subscription "f242b580-3652-46a4-8717-bf0b973ef7c7"
$subscriptions = "f242b580-3652-46a4-8717-bf0b973ef7c7"
#Get-AzSubscription

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

# Register resource providers for each subscription
foreach ($subscription in $subscriptions) {
    Set-AzContext -SubscriptionId "f242b580-3652-46a4-8717-bf0b973ef7c7"
    foreach ($provider in $providers) {
        if (-not (Get-AzResourceProvider -ProviderNamespace $provider)) {
            Register-AzResourceProvider -ProviderNamespace $provider
        }
    }
}