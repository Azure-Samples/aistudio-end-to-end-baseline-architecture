/*
  Deploy machine learning workspace, private endpoints and compute resources
*/

@description('This is the base name for each Azure resource name (6-8 chars)')
param baseName string

@description('The resource group location')
param location string = resourceGroup().location

// existing resource name params 
param vnetName string
param privateEndpointsSubnetName string
param applicationInsightsName string
param containerRegistryName string
param keyVaultName string
param mlStorageAccountName string
param openAiResourceName string
param searchServiceName string
param cognitiveAccountName string // Added parameter for cognitive account

// ---- Variables ----
var workspaceName = 'mlw-${baseName}'
var aiStudioHubName = 'aihub-${baseName}'

// ---- Existing resources ----
resource vnet 'Microsoft.Network/virtualNetworks@2023-05-01' existing = {
  name: vnetName

  resource privateEndpointsSubnet 'subnets' existing = {
    name: privateEndpointsSubnetName
  }
}

resource applicationInsights 'Microsoft.Insights/components@2020-02-02' existing = {
  name: applicationInsightsName
}

resource containerRegistry 'Microsoft.ContainerRegistry/registries@2023-08-01-preview' existing = {
  name: containerRegistryName
}

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: keyVaultName
}

resource mlStorage 'Microsoft.Storage/storageAccounts@2023-01-01' existing = {
  name: mlStorageAccountName
}

resource openAiAccount 'Microsoft.CognitiveServices/accounts@2023-05-01' existing = {
  name: openAiResourceName
}

resource searchService 'Microsoft.Search/searchServices@2021-04-01-preview' existing = {
  name: searchServiceName
}

resource cognitiveAccount 'Microsoft.CognitiveServices/accounts@2024-04-01-preview' existing = { // Added resource for cognitive account
  name: cognitiveAccountName
}

@description('Built-in Role: [AcrPull](https://learn.microsoft.com/azure/role-based-access-control/built-in-roles#acrpull)')
resource containerRegistryPullRole 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  name: '7f951dda-4ed3-4680-a7ca-43fe172d538d'
  scope: subscription()
}

@description('Built-in Role: [AcrPush](https://learn.microsoft.com/azure/role-based-access-control/built-in-roles#acrpush)')
resource containerRegistryPushRole 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  name: '8311e382-0749-4cb8-b61a-304f252e45ec'
  scope: subscription()
}

// ---- Machine Learning Workspace assets ----

@description('Azure region of the deployment')
param aiHubLocation string
@description('Tags to add to the resources')
param aiHubTags object
@description('AI hub description')
param aiHubDescription string
param aiServicesEndpoint string

@description('Azure AI Studio Hub.')
resource aiStudioHub 'Microsoft.MachineLearningServices/workspaces@2024-07-01-preview' = {
  name: aiStudioHubName
  location: aiHubLocation
  tags: aiHubTags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    friendlyName: workspaceName
    description: aiHubDescription

    // dependent resources
    applicationInsights: applicationInsights.id
    containerRegistry: containerRegistry.id
    keyVault: keyVault.id
    storageAccount: mlStorage.id
    systemDatastoresAuthMode: 'identity'

    // configuration for workspaces with private link endpoint

    publicNetworkAccess: 'Disabled'

    managedNetwork: {
      isolationMode: 'AllowInternetOutBound'
      outboundRules: {
        search: {
          type: 'PrivateEndpoint'
          destination: {
            serviceResourceId: searchService.id
            subresourceTarget: 'searchService'
            sparkEnabled: false
            sparkStatus: 'Inactive'
          }
        }

        aiservices: {
          type: 'PrivateEndpoint'
          destination: {
            serviceResourceId: cognitiveAccount.id // Updated to use cognitive account
            subresourceTarget: 'account'
            sparkEnabled: false
            sparkStatus: 'Inactive'
          }
        }
      
      }
    }
  }
  kind: 'hub'

  resource aiServicesConnection 'connections@2024-01-01-preview' = {
    name: '${aiStudioHubName}-connection-AIServices'
    properties: {
      category: 'AIServices'
      target: aiServicesEndpoint
      authType: 'AAD'
      isSharedToAll: true

      metadata: {
        ApiType: 'Azure'
        ResourceId: openAiAccount.id
      }
    }
  }
}

output aiStudioHubId string = aiStudioHub.id

resource machineLearningPrivateEndpoint 'Microsoft.Network/privateEndpoints@2023-05-01' = {
  name: 'pep-${workspaceName}'
  location: location
  properties: {
    privateLinkServiceConnections: [
      {
        name: 'pep-${workspaceName}'
        properties: {
          groupIds: [
            'amlworkspace'
          ]
          privateLinkServiceId: aiStudioHub.id
        }
      }
    ]
    subnet: {
      id: vnet::privateEndpointsSubnet.id
    }
  }

  resource privateEndpointDns 'privateDnsZoneGroups' = {
    name: 'amlworkspace-PrivateDnsZoneGroup'
    properties: {
      privateDnsZoneConfigs: [
        {
          name: 'privatelink.api.azureml.ms'
          properties: {
            privateDnsZoneId: amlPrivateDnsZone.id
          }
        }
        {
          name: 'privatelink.notebooks.azure.net'
          properties: {
            privateDnsZoneId: notebookPrivateDnsZone.id
          }
        }
      ]
    }
  }
}

resource amlPrivateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'privatelink.api.azureml.ms'
  location: 'global'

  resource amlPrivateDnsZoneVnetLink 'virtualNetworkLinks' = {
    name: '${amlPrivateDnsZone.name}-link'
    location: 'global'
    properties: {
      registrationEnabled: false
      virtualNetwork: {
        id: vnet.id
      }
    }
  }
}

// Notebook
resource notebookPrivateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'privatelink.notebooks.azure.net'
  location: 'global'

  resource notebookPrivateDnsZoneVnetLink 'virtualNetworkLinks' = {
    name: '${notebookPrivateDnsZone.name}-link'
    location: 'global'
    properties: {
      registrationEnabled: false
      virtualNetwork: {
        id: vnet.id
      }
    }
  }
}

// AMLW -> Azure Container Registry data plane (push and pull)

@description('Assign AML Workspace\'s ID: AcrPush to workload\'s container registry.')
resource containerRegistryPushRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: containerRegistry
  name: guid(containerRegistry.id, aiStudioHub.name, containerRegistryPushRole.id,containerRegistryName)
  properties: {
    roleDefinitionId: containerRegistryPushRole.id
    principalType: 'ServicePrincipal'
    principalId: aiStudioHub.identity.principalId
  }
}

@description('Assign AML Workspace\'s Managed Online Endpoint: AcrPull to workload\'s container registry.')
resource computeInstanceContainerRegistryPullRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: containerRegistry
  name: guid(containerRegistry.id, aiStudioHub.name, containerRegistryPullRole.id,containerRegistryName)
  properties: {
    roleDefinitionId: containerRegistryPullRole.id
    principalType: 'ServicePrincipal'
    principalId: aiStudioHub.identity.principalId
  }
}

output machineLearningId string = aiStudioHub.id
