// Azure AI Foundry Hub + Project with private endpoints

param hubName string
param projectName string
param location string
param tags object
param privateEndpointSubnetId string
param vnetId string
param keyVaultId string
param storageAccountName string
param logAnalyticsWorkspaceName string

resource logWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = {
  name: logAnalyticsWorkspaceName
}

// ── Storage account for Foundry hub ──────────────────────────────────────

resource foundryStorage 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageAccountName
  location: location
  tags: tags
  sku: { name: 'Standard_LRS' }
  kind: 'StorageV2'
  properties: {
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    publicNetworkAccess: 'Disabled'
  }
}

// ── Private DNS zones ─────────────────────────────────────────────────────

resource cogServicesDns 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'privatelink.cognitiveservices.azure.com'
  location: 'global'
  tags: tags
}

resource cogServicesDnsLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: cogServicesDns
  name: 'link-cog-${hubName}'
  location: 'global'
  properties: {
    virtualNetwork: { id: vnetId }
    registrationEnabled: false
  }
}

resource openAiDns 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'privatelink.openai.azure.com'
  location: 'global'
  tags: tags
}

resource openAiDnsLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: openAiDns
  name: 'link-oai-${hubName}'
  location: 'global'
  properties: {
    virtualNetwork: { id: vnetId }
    registrationEnabled: false
  }
}

resource aiProjectsDns 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'privatelink.api.azureml.ms'
  location: 'global'
  tags: tags
}

resource aiProjectsDnsLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: aiProjectsDns
  name: 'link-aip-${hubName}'
  location: 'global'
  properties: {
    virtualNetwork: { id: vnetId }
    registrationEnabled: false
  }
}

// ── Foundry Hub (AI Services resource) ───────────────────────────────────

resource foundryHub 'Microsoft.MachineLearningServices/workspaces@2024-10-01' = {
  name: hubName
  location: location
  tags: tags
  kind: 'Hub'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    friendlyName: hubName
    publicNetworkAccess: 'Disabled'
    keyVault: keyVaultId
    storageAccount: foundryStorage.id
  }
}

// ── Private endpoint for Foundry Hub ─────────────────────────────────────

resource hubPe 'Microsoft.Network/privateEndpoints@2024-01-01' = {
  name: 'pe-${hubName}'
  location: location
  tags: tags
  properties: {
    subnet: { id: privateEndpointSubnetId }
    privateLinkServiceConnections: [
      {
        name: 'plsc-${hubName}'
        properties: {
          privateLinkServiceId: foundryHub.id
          groupIds: ['amlworkspace']
        }
      }
    ]
  }
}

resource hubPeDnsGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-01-01' = {
  parent: hubPe
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'api-azureml-ms'
        properties: { privateDnsZoneId: aiProjectsDns.id }
      }
    ]
  }
}

// ── Foundry Project ───────────────────────────────────────────────────────

resource foundryProject 'Microsoft.MachineLearningServices/workspaces@2024-10-01' = {
  name: projectName
  location: location
  tags: tags
  kind: 'Project'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    friendlyName: projectName
    hubResourceId: foundryHub.id
    publicNetworkAccess: 'Disabled'
  }
}

// ── Diagnostics ───────────────────────────────────────────────────────────

resource hubDiag 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'diag-${hubName}'
  scope: foundryHub
  properties: {
    workspaceId: logWorkspace.id
    logs: [{ categoryGroup: 'allLogs', enabled: true }]
    metrics: [{ category: 'AllMetrics', enabled: true }]
  }
}

// ── Outputs ───────────────────────────────────────────────────────────────

output hubResourceId string = foundryHub.id
output hubName string = foundryHub.name
output projectResourceId string = foundryProject.id
output projectName string = foundryProject.name
output projectEndpoint string = 'https://${foundryProject.name}.api.azureml.ms'
output principalId string = foundryHub.identity.principalId
