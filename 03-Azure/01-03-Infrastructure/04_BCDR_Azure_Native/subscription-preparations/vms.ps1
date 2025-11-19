
# Replace 'westeurope' with your desired region
$region = "westeurope"

# Get all VM sizes in the region and filter for Standard_D v5 or v6
Get-AzVMSize -Location $region | Where-Object {
    $_.Name -like "Standard_D*v5" -or $_.Name -like "Standard_D*v6"
} | Select-Object Name, NumberOfCores, MemoryInMB, MaxDataDiskCount
