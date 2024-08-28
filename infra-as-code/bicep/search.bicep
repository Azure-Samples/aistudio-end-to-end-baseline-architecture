metadata description = 'Creates an Azure AI Search instance.'
param name string
param location string = resourceGroup().location
param tags object = {}
param vnetName string
param privateEndpointsSubnetName string
param sku object = {
  name: 'standard'
}

param authOptions object = {}
param disableLocalAuth bool = false
param encryptionWithCmk object = {
  enforcement: 'Unspecified'
}
@allowed([
  'default'
  'highDensity'
])
param hostingMode string = 'default'
@allowed([
  'enabled'
  'disabled'
])
param publicNetworkAccess string = 'disabled'
param partitionCount int = 1
param replicaCount int = 1
@allowed([
  'disabled'
  'free'
  'standard'
])
param semanticSearch string = 'free'

param sharedPrivateLinks array = [] // Add this line
param deploySharedPrivateLink bool = true // Add this line

param searchDnsZoneName string = 'privatelink.search.windows.net'
param searchDnsGroupName string = '${name}-privateEndpoint/default'

var searchIdentityProvider = (sku.name == 'free')
  ? null
  : {
      type: 'SystemAssigned'
    }

resource search 'Microsoft.Search/searchServices@2024-03-01-preview' = {
  name: name
  location: location
  tags: tags
  // The free tier does not support managed identity
  identity: searchIdentityProvider
  properties: {
    authOptions: disableLocalAuth
      ? null
      : {
          aadOrApiKey: {
            aadAuthFailureMode: 'http401WithBearerChallenge'
          }
        }
    disableLocalAuth: disableLocalAuth
    encryptionWithCmk: encryptionWithCmk
    hostingMode: hostingMode
    partitionCount: partitionCount
    publicNetworkAccess: publicNetworkAccess
    replicaCount: replicaCount
    semanticSearch: semanticSearch
    networkRuleSet: {
      ipRules: []
      bypass: 'AzureServices'
    }
  }
  sku: sku
  
  @batchSize(1)
resource sharedPrivateLinkResource 'sharedPrivateLinkResources@2024-06-01-preview' =  [for (splResource, i) in sharedPrivateLinks: if(deploySharedPrivateLink) {
      name: 'search-shared-private-link-${i}'
      properties: splResource // splResource contains the properties for each resource
  }]
}

resource vnet 'Microsoft.Network/virtualNetworks@2022-11-01' existing = {
  name: vnetName

  resource privateEndpointsSubnet 'subnets' existing = {
    name: privateEndpointsSubnetName
  }
}

resource privateEndpoint 'Microsoft.Network/privateEndpoints@2021-02-01' = {
  name: '${name}-privateEndpoint'
  location: location
  properties: {
    privateLinkServiceConnections: [
      {
        name: 'searchServiceConnection'
        properties: {
          privateLinkServiceId: search.id
          groupIds: [
            'searchService'
          ]
        }
      }
    ]
    subnet: {
      id: vnet::privateEndpointsSubnet.id
    }
  }
}

resource searchDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: searchDnsZoneName
  location: 'global'
  properties: {}
}

resource searchDnsZoneLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: searchDnsZone
  name: '${searchDnsZoneName}-link'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnet.id
    }
  }
}

resource searchDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2022-11-01' = {
  name: searchDnsGroupName
  properties: {
    privateDnsZoneConfigs: [
      {
        name: searchDnsZoneName
        properties: {
          privateDnsZoneId: searchDnsZone.id
        }
      }
    ]
  }
  dependsOn: [
    privateEndpoint
  ]
}

output id string = search.id
output endpoint string = 'https://${name}.search.windows.net/'
output name string = search.name
output principalId string = !empty(searchIdentityProvider) ? search.identity.principalId : ''
