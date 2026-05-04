// APIM Developer SKU with VNet injection
// apimMode = 'External' → public inbound (Stage 2)
// apimMode = 'Internal' → VNet-only inbound (Stage 3+)

param name string
param location string
param tags object
@allowed(['External', 'Internal'])
param virtualNetworkType string = 'External'
param apimSubnetId string
param logAnalyticsWorkspaceName string

resource logWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = {
  name: logAnalyticsWorkspaceName
}

resource apim 'Microsoft.ApiManagement/service@2023-09-01-preview' = {
  name: name
  location: location
  tags: tags
  sku: {
    name: 'Developer'
    capacity: 1
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    publisherEmail: 'admin@contoso.com'
    publisherName: 'Contoso Demo'
    virtualNetworkType: virtualNetworkType
    virtualNetworkConfiguration: {
      subnetResourceId: apimSubnetId
    }
    customProperties: {
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Protocols.Tls10': 'false'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Protocols.Tls11': 'false'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Protocols.Ssl30': 'false'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Backend.Protocols.Tls10': 'false'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Backend.Protocols.Tls11': 'false'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Backend.Protocols.Ssl30': 'false'
    }
  }
}

// ── Backend pointing to AKS Internal LB ──────────────────────────────────
// The AKS Internal LB IP is set after cluster deployment.
// This backend uses a placeholder — update via azd env var post-deploy.

resource apimBackend 'Microsoft.ApiManagement/service/backends@2023-09-01-preview' = {
  parent: apim
  name: 'aks-chat-backend'
  properties: {
    description: 'AKS chat app internal load balancer'
    url: 'http://10.0.0.100'  // Updated post-deployment with actual AKS LB IP
    protocol: 'http'
    tls: {
      validateCertificateChain: false
      validateCertificateName: false
    }
  }
}

// ── API definition ────────────────────────────────────────────────────────

resource chatApi 'Microsoft.ApiManagement/service/apis@2023-09-01-preview' = {
  parent: apim
  name: 'chat-api'
  properties: {
    displayName: 'Chat API'
    path: 'chat'
    protocols: ['https']
    subscriptionRequired: false
    serviceUrl: 'http://10.0.0.100'  // AKS Internal LB
  }
}

resource chatApiAllOps 'Microsoft.ApiManagement/service/apis/operations@2023-09-01-preview' = {
  parent: chatApi
  name: 'chat-post'
  properties: {
    displayName: 'Chat'
    method: 'POST'
    urlTemplate: '/message'
    request: {
      description: 'Chat message'
    }
    responses: []
  }
}

// Forward all requests to AKS backend
resource chatApiPolicy 'Microsoft.ApiManagement/service/apis/policies@2023-09-01-preview' = {
  parent: chatApi
  name: 'policy'
  properties: {
    format: 'xml'
    value: '''
<policies>
  <inbound>
    <base />
    <set-backend-service backend-id="aks-chat-backend" />
  </inbound>
  <backend>
    <base />
  </backend>
  <outbound>
    <base />
  </outbound>
  <on-error>
    <base />
  </on-error>
</policies>
'''
  }
}

// ── Diagnostics ───────────────────────────────────────────────────────────

resource apimDiag 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'diag-${name}'
  scope: apim
  properties: {
    workspaceId: logWorkspace.id
    logs: [{ categoryGroup: 'allLogs', enabled: true }]
    metrics: [{ category: 'AllMetrics', enabled: true }]
  }
}

// ── Outputs ───────────────────────────────────────────────────────────────

output resourceId string = apim.id
output resourceName string = apim.name
output gatewayUrl string = apim.properties.gatewayUrl
output principalId string = apim.identity.principalId
// Private link service ID used by AFD Premium origin
output privateLinkServiceId string = apim.id
