// Azure AI Foundry Hub + Project with private endpoints and Azure OpenAI backend

param hubName string
param projectName string
param openAiName string
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

// ── Azure OpenAI resource ─────────────────────────────────────────────────

resource openAi 'Microsoft.CognitiveServices/accounts@2024-10-01' = {
  name: openAiName
  location: location
  tags: tags
  kind: 'OpenAI'
  sku: { name: 'S0' }
  properties: {
    customSubDomainName: openAiName
    publicNetworkAccess: 'Disabled'
  }
}

resource gpt4oDeployment 'Microsoft.CognitiveServices/accounts/deployments@2024-10-01' = {
  parent: openAi
  name: 'gpt-4o'
  sku: {
    name: 'Standard'
    capacity: 30
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: 'gpt-4o'
      version: '2024-11-20'
    }
  }
}

// ── Private endpoint for OpenAI ───────────────────────────────────────────

resource openAiPe 'Microsoft.Network/privateEndpoints@2024-01-01' = {
  name: 'pe-${openAiName}'
  location: location
  tags: tags
  dependsOn: [gpt4oDeployment]
  properties: {
    subnet: { id: privateEndpointSubnetId }
    privateLinkServiceConnections: [
      {
        name: 'plsc-${openAiName}'
        properties: {
          privateLinkServiceId: openAi.id
          groupIds: ['account']
        }
      }
    ]
  }
}

resource openAiPeDnsGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-01-01' = {
  parent: openAiPe
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'openai-azure-com'
        properties: { privateDnsZoneId: openAiDns.id }
      }
      {
        name: 'cognitiveservices-azure-com'
        properties: { privateDnsZoneId: cogServicesDns.id }
      }
    ]
  }
}

// ── Hub connection to OpenAI ──────────────────────────────────────────────

resource hubOpenAiConnection 'Microsoft.MachineLearningServices/workspaces/connections@2024-10-01' = {
  parent: foundryHub
  name: '${openAiName}-connection'
  properties: {
    category: 'AzureOpenAI'
    target: openAi.properties.endpoint
    authType: 'ApiKey'
    isSharedToAll: true
    credentials: {
      key: openAi.listKeys().key1
    }
    metadata: {
      ApiVersion: '2024-10-21'
      ApiType: 'azure'
      ResourceId: openAi.id
    }
  }
  dependsOn: [gpt4oDeployment]
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
output openAiResourceId string = openAi.id
output openAiEndpoint string = openAi.properties.endpoint
