param storageAccountName string
param mlWorkspaceResourceId string
param location string = resourceGroup().location
param resourceGroupName string = resourceGroup().name
param forceUpdateTagValue string = utcNow()
param tenantId string = subscription().tenantId

var identityName = 'userAssignedIdentity'
var roleDefinitionId = 'b24988ac-6180-42a0-ab88-20f7382dd24c' // Contributor role

// Create User-Assigned Managed Identity
resource userAssignedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: identityName
  location: location
}

// Role Assignment
resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: resourceGroup()
  name: guid(subscription().id, userAssignedIdentity.id, roleDefinitionId)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleDefinitionId)
    principalId: userAssignedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// Update Network ACL using Azure CLI
resource updateNetworkAclScript 'Microsoft.Resources/deploymentScripts@2020-10-01' = {
  name: 'updateNetworkAclScript'
  location: location
  kind: 'AzureCLI'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${userAssignedIdentity.id}': {}
    }
  }
  properties: {
    forceUpdateTag: forceUpdateTagValue
    azCliVersion: '2.37.0'
    timeout: 'PT10M'
    scriptContent: 'az storage account network-rule add --account-name ${storageAccountName} --resource-group ${resourceGroupName} --resource-id ${mlWorkspaceResourceId} --tenant-id ${tenantId}'
    cleanupPreference: 'OnSuccess'
    retentionInterval: 'P1D'
  }
  dependsOn: [
    roleAssignment
  ]
}
