targetScope = 'subscription'

@minLength(1)
@maxLength(64)
@description('Name of the environment used to generate resource names')
param environmentName string

@minLength(1)
@description('Primary location for all resources')
param location string

@description('Name of the resource group')
param resourceGroupName string = 'rg-${environmentName}'

var resourceToken = uniqueString(subscription().id, location, environmentName)

// Resource Group
resource rg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: resourceGroupName
  location: location
  tags: {
    'azd-env-name': environmentName
  }
}

// User-Assigned Managed Identity
module identity 'modules/identity.bicep' = {
  name: 'identity'
  scope: rg
  params: {
    location: location
    resourceToken: resourceToken
  }
}

// Monitoring: Log Analytics Workspace + Application Insights
module monitoring 'modules/monitoring.bicep' = {
  name: 'monitoring'
  scope: rg
  params: {
    location: location
    resourceToken: resourceToken
  }
}

// Azure Container Registry
module acr 'modules/acr.bicep' = {
  name: 'acr'
  scope: rg
  params: {
    location: location
    resourceToken: resourceToken
    identityPrincipalId: identity.outputs.principalId
  }
}

// Container Apps Environment + Container App (Docker)
module web 'modules/web.bicep' = {
  name: 'web'
  scope: rg
  params: {
    location: location
    resourceToken: resourceToken
    identityId: identity.outputs.id
    acrLoginServer: acr.outputs.loginServer
    appInsightsConnectionString: monitoring.outputs.appInsightsConnectionString
    logAnalyticsName: monitoring.outputs.logAnalyticsName
  }
}

// Azure AI Foundry: Hub, Project, AI Services, Model Deployments
module ai 'modules/ai.bicep' = {
  name: 'ai'
  scope: rg
  params: {
    location: location
    resourceToken: resourceToken
    appInsightsId: monitoring.outputs.appInsightsId
  }
}

// Required outputs
output RESOURCE_GROUP_ID string = rg.id
output AZURE_CONTAINER_REGISTRY_ENDPOINT string = acr.outputs.loginServer
output ACR_LOGIN_SERVER string = acr.outputs.loginServer
output WEB_APP_URL string = web.outputs.appUrl
output AI_HUB_NAME string = ai.outputs.hubName
output AI_PROJECT_NAME string = ai.outputs.projectName
