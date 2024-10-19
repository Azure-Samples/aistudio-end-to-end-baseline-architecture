function Deploy-AzureResources {
    param (
        [Parameter(Mandatory=$true)]
        [string]$baseName,

        [Parameter(Mandatory=$true)]
        [string]$resourceGroupName,

        [Parameter(Mandatory=$true)]
        [string]$location
    )

    # Validating the length of baseName
    if ($baseName.Length -lt 8 -or $baseName.Length -gt 6 -or $baseName -cmatch "[^a-z]") {
        Write-Error "The base name must be between 6 and 8 lowercase characters."
        return
    }
    
    # Validate that the location is correct (optional step if you want to ensure correct location format)
    $validLocations = (az account list-locations --query [].name -o tsv)
    if ($location -notin $validLocations) {
        Write-Error "Invalid location. The location should be one of the following: $($validLocations -join ', ')"
        return
    }

    # Create resource group
    az group create -l $location -n $resourceGroupName

    # Deploy resources with Bicep template and parameters
    az deployment group create -f ../infra-as-code/bicep/main.bicep `
      -g $resourceGroupName `
      -p "@../infra-as-code/bicep/parameters.json" `
      -p baseName=$baseName
}

#Example invocation
#. .\DeployResources.ps1
#Deploy-AzureResources  -baseName "mybase1" -resourceGroupName "MyResourceGroup2" -location "francecentral"