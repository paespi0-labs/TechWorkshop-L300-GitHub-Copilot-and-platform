param location string
param logAnalyticsWorkspaceId string

resource workbook 'Microsoft.Insights/workbooks@2022-04-01' = {
  name: guid(resourceGroup().id, 'ai-services-observability')
  location: location
  kind: 'shared'
  properties: {
    displayName: 'AI Services Observability'
    category: 'workbook'
    sourceId: logAnalyticsWorkspaceId
    serializedData: loadTextContent('../workbook.json')
  }
}
