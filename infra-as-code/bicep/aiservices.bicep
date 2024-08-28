// Creates AI services resources, private endpoints, and DNS zones
@description('Azure region of the deployment')
param location string

@description('Tags to add to the resources')
param tags object

@description('Name of the AI service')
param aiServiceName string

@description('Name of the AI service private link endpoint for cognitive services')
param aiServicesPleName string


param vnetName string
param privateEndpointsSubnetName string
@description('AI service SKU')
param aiServiceSkuName string = 'S0'

@description('Disable local authentication')
param disableLocalAuth bool = false

var aiServiceNameCleaned = replace(aiServiceName, '-', '')

var cognitiveServicesPrivateDnsZoneName = 'privatelink.cognitiveservices.azure.com'
var openAiPrivateDnsZoneName = 'privatelink.openai.azure.com'

resource vnet 'Microsoft.Network/virtualNetworks@2022-11-01' existing = {
  name: vnetName

  resource privateEndpointsSubnet 'subnets' existing = {
    name: privateEndpointsSubnetName
  }
}


resource aiServices 'Microsoft.CognitiveServices/accounts@2024-04-01-preview' = {
  name: aiServiceNameCleaned
  location: location
  sku: {
    name: aiServiceSkuName
  }
  kind: 'AIServices'
  properties: {
    publicNetworkAccess: 'disabled'
    disableLocalAuth: disableLocalAuth
    apiProperties: {
      statisticsEnabled: false
    }
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Deny'
      virtualNetworkRules: [
        {
          id: vnet::privateEndpointsSubnet.id
          ignoreMissingVnetServiceEndpoint: true
        }
      ]
      
    }
    customSubDomainName: aiServiceNameCleaned
  }
  identity: {
    type: 'SystemAssigned'
  }
}

resource aiServicesPrivateEndpoint 'Microsoft.Network/privateEndpoints@2023-11-01' = {
  name: aiServicesPleName
  location: location
  tags: tags
  properties: {
    privateLinkServiceConnections: [
      { 
        name: aiServicesPleName
        properties: {
          groupIds: [
            'account'
          ]
          privateLinkServiceId: aiServices.id
        }
      }
    ]
    subnet: {
      id: vnet::privateEndpointsSubnet.id
    }
  }
}

resource cognitiveServicesPrivateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: cognitiveServicesPrivateDnsZoneName
  location: 'global'
}

resource openAiPrivateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: openAiPrivateDnsZoneName
  location: 'global'
}

resource cognitiveServicesVnetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: cognitiveServicesPrivateDnsZone
  name: uniqueString(vnet.id)
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnet.id
    }
  }
}

resource openAiVnetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: openAiPrivateDnsZone
  name: uniqueString(vnet.id)
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnet.id
    }
  }
}

resource aiServicesPrivateDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-11-01' = {
  parent: aiServicesPrivateEndpoint
  name: 'default'
  properties:{
    privateDnsZoneConfigs: [
      {
        name: replace(openAiPrivateDnsZoneName, '.', '-')
        properties:{
          privateDnsZoneId: openAiPrivateDnsZone.id
        }
      }
      {
        name: replace(cognitiveServicesPrivateDnsZoneName, '.', '-')
        properties:{
          privateDnsZoneId: cognitiveServicesPrivateDnsZone.id
        }
      }
    ]
  }
}
output name string = aiServices.name
output aiServicesId string = aiServices.id
output aiServicesEndpoint string = aiServices.properties.endpoint
output openAiId string = aiServices.id
output aiServicesPrincipalId string = aiServices.identity.principalId
