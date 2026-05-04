// Networking module — VNet + 6 subnets + NSGs

param vnetName string
param location string
param tags object
param logAnalyticsWorkspaceName string

resource logWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = {
  name: logAnalyticsWorkspaceName
}

// ── NSGs ──────────────────────────────────────────────────────────────────

resource nsgAks 'Microsoft.Network/networkSecurityGroups@2024-01-01' = {
  name: 'nsg-aks-${vnetName}'
  location: location
  tags: tags
  properties: {
    securityRules: []
  }
}

resource nsgVm 'Microsoft.Network/networkSecurityGroups@2024-01-01' = {
  name: 'nsg-vm-${vnetName}'
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'AllowBastionInbound'
        properties: {
          priority: 100
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Inbound'
          sourceAddressPrefix: '10.0.5.0/26'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRanges: ['3389', '22']
        }
      }
      {
        name: 'DenyAllInbound'
        properties: {
          priority: 4096
          protocol: '*'
          access: 'Deny'
          direction: 'Inbound'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '*'
        }
      }
    ]
  }
}

resource nsgApim 'Microsoft.Network/networkSecurityGroups@2024-01-01' = {
  name: 'nsg-apim-${vnetName}'
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'AllowAPIMManagement'
        properties: {
          priority: 100
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Inbound'
          sourceAddressPrefix: 'ApiManagement'
          sourcePortRange: '*'
          destinationAddressPrefix: 'VirtualNetwork'
          destinationPortRange: '3443'
        }
      }
      {
        name: 'AllowHTTPS'
        properties: {
          priority: 200
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Inbound'
          sourceAddressPrefix: 'Internet'
          sourcePortRange: '*'
          destinationAddressPrefix: 'VirtualNetwork'
          destinationPortRange: '443'
        }
      }
      {
        name: 'AllowHTTP'
        properties: {
          priority: 210
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Inbound'
          sourceAddressPrefix: 'Internet'
          sourcePortRange: '*'
          destinationAddressPrefix: 'VirtualNetwork'
          destinationPortRange: '80'
        }
      }
      {
        name: 'AllowAzureLoadBalancer'
        properties: {
          priority: 300
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Inbound'
          sourceAddressPrefix: 'AzureLoadBalancer'
          sourcePortRange: '*'
          destinationAddressPrefix: 'VirtualNetwork'
          destinationPortRange: '6390'
        }
      }
    ]
  }
}

resource nsgPe 'Microsoft.Network/networkSecurityGroups@2024-01-01' = {
  name: 'nsg-pe-${vnetName}'
  location: location
  tags: tags
  properties: {
    securityRules: []
  }
}

// ── VNet ──────────────────────────────────────────────────────────────────

module vnet 'br/public:avm/res/network/virtual-network:0.5.0' = {
  name: '${vnetName}-deploy'
  params: {
    name: vnetName
    location: location
    tags: tags
    addressPrefixes: ['10.0.0.0/16']
    subnets: [
      {
        name: 'snet-aks'
        addressPrefix: '10.0.0.0/22'
        networkSecurityGroupResourceId: nsgAks.id
        privateEndpointNetworkPolicies: 'Disabled'
      }
      {
        name: 'snet-vm'
        addressPrefix: '10.0.4.0/24'
        networkSecurityGroupResourceId: nsgVm.id
      }
      {
        name: 'AzureBastionSubnet'
        addressPrefix: '10.0.5.0/26'
      }
      {
        name: 'snet-apim'
        addressPrefix: '10.0.6.0/24'
        networkSecurityGroupResourceId: nsgApim.id
      }
      {
        name: 'snet-pe'
        addressPrefix: '10.0.7.0/24'
        networkSecurityGroupResourceId: nsgPe.id
        privateEndpointNetworkPolicies: 'Disabled'
      }
      {
        name: 'snet-afd-pe'
        addressPrefix: '10.0.8.0/24'
        privateEndpointNetworkPolicies: 'Disabled'
      }
    ]
    diagnosticSettings: [
      {
        workspaceResourceId: logWorkspace.id
        logCategoriesAndGroups: [{ categoryGroup: 'allLogs' }]
        metricCategories: [{ category: 'AllMetrics' }]
      }
    ]
  }
}

// ── Outputs ──────────────────────────────────────────────────────────────

output vnetId string = vnet.outputs.resourceId
output vnetName string = vnet.outputs.name
output aksSubnetId string = vnet.outputs.subnetResourceIds[0]
output vmSubnetId string = vnet.outputs.subnetResourceIds[1]
output bastionSubnetId string = vnet.outputs.subnetResourceIds[2]
output apimSubnetId string = vnet.outputs.subnetResourceIds[3]
output peSubnetId string = vnet.outputs.subnetResourceIds[4]
output afdPeSubnetId string = vnet.outputs.subnetResourceIds[5]
