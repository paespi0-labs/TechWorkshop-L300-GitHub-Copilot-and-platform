param location string
param resourceToken string
param appInsightsId string
param identityPrincipalId string
param logAnalyticsWorkspaceId string

// Storage Account required by AI Foundry Hub
resource storage 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: 'azst${resourceToken}'
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
  }
}

// Key Vault required by AI Foundry Hub
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: 'azkv${resourceToken}'
  location: location
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: subscription().tenantId
    enableRbacAuthorization: true
  }
}

// Azure AI Services account for model deployments
resource aiServices 'Microsoft.CognitiveServices/accounts@2024-10-01' = {
  name: 'azais${resourceToken}'
  location: location
  kind: 'AIServices'
  sku: {
    name: 'S0'
  }
  properties: {
    customSubDomainName: 'azais${resourceToken}'
    publicNetworkAccess: 'Enabled'
    disableLocalAuth: true
  }
}

// GPT-4o model deployment
resource gpt4oDeployment 'Microsoft.CognitiveServices/accounts/deployments@2024-10-01' = {
  parent: aiServices
  name: 'gpt-4o'
  sku: {
    name: 'Standard'
    capacity: 10
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: 'gpt-4o'
      version: '2024-08-06'
    }
  }
}

// NOTE: Phi-4 must be deployed as a serverless endpoint via AI Foundry portal after provisioning.
// CognitiveServices account deployments do not support Microsoft-format models like Phi-4.

// AI Foundry Hub
resource aiHub 'Microsoft.MachineLearningServices/workspaces@2024-10-01' = {
  name: 'azhub${resourceToken}'
  location: location
  kind: 'Hub'
  sku: {
    name: 'Basic'
    tier: 'Basic'
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    friendlyName: 'ZavaStorefront AI Hub'
    storageAccount: storage.id
    keyVault: keyVault.id
    applicationInsights: appInsightsId
    publicNetworkAccess: 'Enabled'
  }
}

// Connection from AI Hub to AI Services
resource aiHubConnection 'Microsoft.MachineLearningServices/workspaces/connections@2024-10-01' = {
  parent: aiHub
  name: 'aiservices-connection'
  properties: {
    category: 'AIServices'
    target: aiServices.properties.endpoint
    authType: 'AAD'
    isSharedToAll: true
    metadata: {
      ApiType: 'Azure'
      ResourceId: aiServices.id
    }
  }
}

// AI Foundry Project linked to Hub
resource aiProject 'Microsoft.MachineLearningServices/workspaces@2024-10-01' = {
  name: 'azprj${resourceToken}'
  location: location
  kind: 'Project'
  sku: {
    name: 'Basic'
    tier: 'Basic'
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    friendlyName: 'ZavaStorefront AI Project'
    hubResourceId: aiHub.id
    publicNetworkAccess: 'Enabled'
  }
}

// Role assignment: Cognitive Services User for managed identity on AI Services
resource cognitiveServicesUserRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(aiServices.id, identityPrincipalId, 'a97b65f3-24c7-4388-baec-2e87135dc908')
  scope: aiServices
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'a97b65f3-24c7-4388-baec-2e87135dc908')
    principalId: identityPrincipalId
    principalType: 'ServicePrincipal'
  }
}

// Diagnostic settings: send AI Services logs and metrics to Log Analytics
resource aiDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'ai-diagnostics'
  scope: aiServices
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      {
        category: 'Audit'
        enabled: true
      }
      {
        category: 'RequestResponse'
        enabled: true
      }
      {
        category: 'AzureOpenAIRequestUsage'
        enabled: true
      }
      {
        category: 'Trace'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}

output hubName string = aiHub.name
output projectName string = aiProject.name
output aiServicesEndpoint string = aiServices.properties.endpoint
output hubId string = aiHub.id
output projectId string = aiProject.id
