@description('The location in which all resources should be deployed.')
param location string = resourceGroup().location

@description('This is the base name for each Azure resource name (6-8 chars)')
@minLength(6)
@maxLength(8)
param baseName string

@description('Optional. When true will deploy a cost-optimised environment for development purposes. Note that when this param is true, the deployment is not suitable or recommended for Production environments. Default = false.')
param developmentEnvironment bool = false

@description('Domain name to use for App Gateway')
param customDomainName string = 'contoso.com'

@description('The certificate data for app gateway TLS termination. The value is base64 encoded')
@secure()
param appGatewayListenerCertificate string

@description('The name of the web deploy file. The file should reside in a deploy container in the storage account. Defaults to chatui.zip')
param publishFileName string = 'chatui.zip'

@description('Specifies the password of the administrator account on the Windows jump box.\n\nComplexity requirements: 3 out of 4 conditions below need to be fulfilled:\n- Has lower characters\n- Has upper characters\n- Has a digit\n- Has a special character\n\nDisallowed values: "abc@123", "P@$$w0rd", "P@ssw0rd", "P@ssword123", "Pa$$word", "pass@word1", "Password!", "Password1", "Password22", "iloveyou!"')
@secure()
@minLength(8)
@maxLength(123)
param jumpBoxAdminPassword string

param deploySharedPrivateLink bool = true
// ---- User Object ID ----
// The object ID of the user that will be granted access to the resources to interact with AI Studio
param userObjectId string = 'e8f83374-29a8-4b78-9811-721f84ad37ac'
// ---- Availability Zones ----
var availabilityZones = [ '1', '2', '3' ]

// ---- Log Analytics workspace ----
resource logWorkspace 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: 'log-${baseName}'
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// Deploy vnet with subnets and NSGs
module networkModule 'network.bicep' = {
  name: 'networkDeploy'
  params: {
    location: location
    baseName: baseName
    developmentEnvironment: developmentEnvironment
  }
}

@description('Deploys Azure Bastion and the jump box, which is used for private access to the Azure ML and Azure OpenAI portals.')
module jumpBoxModule 'jumpbox.bicep' = {
  name: 'jumpBoxDeploy'
  params: {
    location: location
    baseName: baseName
    virtualNetworkName: networkModule.outputs.vnetNName
    logWorkspaceName: logWorkspace.name
    jumpBoxAdminName: 'vmadmin'
    jumpBoxAdminPassword: jumpBoxAdminPassword
  }
}

// Deploy storage account with private endpoint and private DNS zone
module storageModule 'storage.bicep' = {
  name: 'storageDeploy'
  params: {
    location: location
    baseName: baseName
    vnetName: networkModule.outputs.vnetNName
    privateEndpointsSubnetName: networkModule.outputs.privateEndpointsSubnetName
    logWorkspaceName: logWorkspace.name
  }
}

// Deploy key vault with private endpoint and private DNS zone
module keyVaultModule 'keyvault.bicep' = {
  name: 'keyVaultDeploy'
  params: {
    location: location
    baseName: baseName
    vnetName: networkModule.outputs.vnetNName
    privateEndpointsSubnetName: networkModule.outputs.privateEndpointsSubnetName
    createPrivateEndpoints: true
    appGatewayListenerCertificate: appGatewayListenerCertificate
    apiKey: 'key'
    logWorkspaceName: logWorkspace.name
  }
}

// Deploy container registry with private endpoint and private DNS zone
module acrModule 'acr.bicep' = {
  name: 'acrDeploy'
  params: {
    location: location
    baseName: baseName
    vnetName: networkModule.outputs.vnetNName
    privateEndpointsSubnetName: networkModule.outputs.privateEndpointsSubnetName
    createPrivateEndpoints: true
    logWorkspaceName: logWorkspace.name
  }
}

// Deploy application insights and log analytics workspace
module appInsightsModule 'applicationinsignts.bicep' = {
  name: 'appInsightsDeploy'
  params: {
    location: location
    baseName: baseName
    logWorkspaceName: logWorkspace.name
  }
}

// Deploy Azure OpenAI service with private endpoint and private DNS zone
module openaiModule 'openai.bicep' = {
  name: 'openaiDeploy'
  params: {
    location: location
    baseName: baseName
    vnetName: networkModule.outputs.vnetNName
    privateEndpointsSubnetName: networkModule.outputs.privateEndpointsSubnetName
    logWorkspaceName: logWorkspace.name
    keyVaultName: keyVaultModule.outputs.keyVaultName
    deployDNS: false
  }
}

module aiServices 'aiservices.bicep' = {
  name: 'aiServicesDeploy'
  params: {
    location: location
    aiServiceName: 'ai${baseName}'
    aiServicesPleName: 'aiservicesple'
    vnetName: networkModule.outputs.vnetNName
    privateEndpointsSubnetName: networkModule.outputs.privateEndpointsSubnetName
    
    tags: {
      
    }
  }
}

module aiStudioModule 'aistudio.bicep' = {
  name: 'aiStudioDeploy'
  params: {
    location: location
    baseName: baseName
    vnetName: networkModule.outputs.vnetNName
    privateEndpointsSubnetName: networkModule.outputs.privateEndpointsSubnetName
    logWorkspaceName: logWorkspace.name
    searchServiceName: aiSearchModule.outputs.name
    
    aiHubDescription: 'AI Hub Description'
    aiHubLocation: location
    aiHubTags: {
      environment: 'Development'
      team: 'AI Team'
    }
    applicationInsightsName: appInsightsModule.outputs.applicationInsightsName
    containerRegistryName: 'cr${baseName}'
    keyVaultName: keyVaultModule.outputs.keyVaultName
    mlStorageAccountName: storageModule.outputs.mlDeployStorageName
    openAiResourceName: 'ai${baseName}'
    aiServicesEndpoint: aiServices.outputs.aiServicesEndpoint
    
    
    }
    dependsOn: [
      aiServices
      
    ]
  }

  //Deploys AI Search with private endpoints and shared private link connections
var sharedPrivateLinkResources = [
  // First storage account with 'blob' groupId
  {
    groupId: 'blob'
    status: 'Approved'
    provisioningState: 'Succeeded'
    requestMessage: 'created using the Bicep template'
    privateLinkResourceId: storageModule.outputs.appDeployStorageId
  }
  // Second storage account with 'blob' groupId
  {
    groupId: 'blob'
    status: 'Approved'
    provisioningState: 'Succeeded'
    requestMessage:  'created using the Bicep template'
    privateLinkResourceId: storageModule.outputs.mlStorageId
  }
  // First OpenAI resource with 'openai' groupId
  {
    groupId: 'openai_account'
    status: 'Approved'
    provisioningState: 'Succeeded'
    requestMessage: 'created using the Bicep template'
    privateLinkResourceId: openaiModule.outputs.openAiResourceId
  }
  // Second OpenAI resource with 'openai' groupId
  {
    groupId: 'cognitiveservices_account'
    status: 'Approved'
    provisioningState: 'Succeeded'
    requestMessage:  'created using the Bicep template'
    privateLinkResourceId: aiServices.outputs.aiServicesId
  }
]
module aiSearchModule 'search.bicep' = {
  name: 'aiSearchDeploy'
  params: {
    name: 'ai-search${baseName}'
    vnetName: networkModule.outputs.vnetNName
    privateEndpointsSubnetName: networkModule.outputs.privateEndpointsSubnetName
    sharedPrivateLinks: sharedPrivateLinkResources
    deploySharedPrivateLink:  deploySharedPrivateLink
    sku: {
      name: 'standard2'
    }
  }
}

  //Deploy an Azure Application Gateway with WAF v2 and a custom domain name.
  module gatewayModule 'gateway.bicep' = {
    name: 'gatewayDeploy'
    params: {
    location: location
    baseName: baseName
    developmentEnvironment: developmentEnvironment
    availabilityZones: availabilityZones
    customDomainName: customDomainName
    appName: webappModule.outputs.appName
    vnetName: networkModule.outputs.vnetNName
    appGatewaySubnetName: networkModule.outputs.appGatewaySubnetName
    keyVaultName: keyVaultModule.outputs.keyVaultName
    gatewayCertSecretUri: keyVaultModule.outputs.gatewayCertSecretUri
    logWorkspaceName: logWorkspace.name
  }
}

// Deploy the web apps for the front end demo ui and the containerised promptflow endpoint
module webappModule 'webapp.bicep' = {
  name: 'webappDeploy'
  params: {
    location: location
    baseName: baseName
    developmentEnvironment: developmentEnvironment
    publishFileName: publishFileName
    keyVaultName: keyVaultModule.outputs.keyVaultName
    storageName: storageModule.outputs.appDeployStorageName
    vnetName: networkModule.outputs.vnetNName
    appServicesSubnetName: networkModule.outputs.appServicesSubnetName
    privateEndpointsSubnetName: networkModule.outputs.privateEndpointsSubnetName
    logWorkspaceName: logWorkspace.name
  }
  dependsOn: [
    //openaiModule
    acrModule
  ]
}

module rbacModule 'rbac.bicep' = {
  name: 'rbacDeploy'
  params:{
    storageAccountName: storageModule.outputs.mlDeployStorageName
    aiSearchName: aiSearchModule.outputs.name
    resourceGroupId: resourceGroup().id
    userObjectId: userObjectId
    aiOpenAIChatName: aiServices.outputs.name
    aiOpenAIEmbeddingName: aiServices.outputs.name
    aiServicesPrincipalId: aiServices.outputs.aiServicesPrincipalId
  }
}
