// Azure Container Registry (Premium) with private endpoint

param name string
param location string
param tags object
param privateEndpointSubnetId string
param vnetId string
param logAnalyticsWorkspaceName string

resource logWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = {
  name: logAnalyticsWorkspaceName
}

module acr 'br/public:avm/res/container-registry/registry:0.6.0' = {
  name: '${name}-deploy'
  params: {
    name: name
    location: location
    tags: tags
    acrSku: 'Premium'
    publicNetworkAccess: 'Disabled'
    zoneRedundancy: 'Disabled'
    diagnosticSettings: [
      {
        workspaceResourceId: logWorkspace.id
        logCategoriesAndGroups: [{ categoryGroup: 'allLogs' }]
        metricCategories: [{ category: 'AllMetrics' }]
      }
    ]
    privateEndpoints: [
      {
        subnetResourceId: privateEndpointSubnetId
        service: 'registry'
        privateDnsZoneGroup: {
          privateDnsZoneGroupConfigs: [
            {
              privateDnsZoneResourceId: acrDnsZone.id
            }
          ]
        }
      }
    ]
  }
}

resource acrDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'privatelink.azurecr.io'
  location: 'global'
  tags: tags
}

resource acrDnsZoneLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: acrDnsZone
  name: 'link-acr-${name}'
  location: 'global'
  properties: {
    virtualNetwork: { id: vnetId }
    registrationEnabled: false
  }
}

output resourceId string = acr.outputs.resourceId
output resourceName string = acr.outputs.name
output loginServer string = acr.outputs.loginServer
output principalId string = ''
