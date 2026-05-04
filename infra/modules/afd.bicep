// Azure Front Door Premium — public frontend, private link origin to APIM
// Only deployed when deployAfd = true (Stage 4)

param name string
param location string
param tags object
param apimPrivateLinkServiceId string
param logAnalyticsWorkspaceName string

resource logWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = {
  name: logAnalyticsWorkspaceName
}

module afd 'br/public:avm/res/cdn/profile:0.7.0' = {
  name: '${name}-deploy'
  params: {
    name: name
    location: location
    tags: tags
    sku: 'Premium_AzureFrontDoor'
    originGroups: [
      {
        name: 'apim-origin-group'
        loadBalancingSettings: {
          sampleSize: 4
          successfulSamplesRequired: 3
          additionalLatencyInMilliseconds: 50
        }
        healthProbeSettings: {
          probePath: '/status-0123456789abcdef'
          probeRequestType: 'HEAD'
          probeProtocol: 'Https'
          probeIntervalInSeconds: 100
        }
        origins: [
          {
            name: 'apim-origin'
            hostName: ''  // Set to APIM internal hostname post-deployment
            httpPort: 80
            httpsPort: 443
            originHostHeader: ''
            priority: 1
            weight: 1000
            enabledState: 'Enabled'
            // Private link to APIM — requires manual approval in portal after deployment
            sharedPrivateLinkResource: {
              privateLink: {
                id: apimPrivateLinkServiceId
              }
              groupId: 'Gateway'
              privateLinkLocation: 'eastus2'
              requestMessage: 'AFD private link to APIM'
            }
          }
        ]
      }
    ]
    afdEndpoints: [
      {
        name: '${name}-endpoint'
        enabledState: 'Enabled'
        routes: [
          {
            name: 'chat-route'
            originGroupName: 'apim-origin-group'
            supportedProtocols: ['Https']
            patternsToMatch: ['/*']
            forwardingProtocol: 'HttpsOnly'
            httpsRedirect: 'Enabled'
            linkToDefaultDomain: 'Enabled'
          }
        ]
      }
    ]
  }
}

// Diagnostics sent via separate resource (AVM CDN profile does not expose diagnosticSettings param)
resource afdDiag 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'diag-${name}'
  scope: afdResource
  properties: {
    workspaceId: logWorkspace.id
    logs: [{ categoryGroup: 'allLogs', enabled: true }]
    metrics: [{ category: 'AllMetrics', enabled: true }]
  }
}

resource afdResource 'Microsoft.Cdn/profiles@2024-02-01' existing = {
  name: name
  dependsOn: [afd]
}

output resourceId string = afd.outputs.resourceId
output resourceName string = afd.outputs.name
output endpointUrl string = 'https://${name}-endpoint.z01.azurefd.net'
output principalId string = ''
