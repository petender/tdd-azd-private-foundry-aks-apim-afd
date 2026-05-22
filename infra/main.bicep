targetScope = 'resourceGroup'

// ─────────────────────────────────────────────
// Parameters
// ─────────────────────────────────────────────
@description('Azure region for all resources')
param location string = 'eastus2'

@description('AZD environment name')
param environmentName string

@description('Project identifier used in resource naming')
param projectName string = 'pfaaa'

@description('APIM deployment mode — External allows public inbound; Internal locks to VNet only')
@allowed(['External', 'Internal'])
param apimMode string = 'External'

@description('Deploy Azure Front Door Premium (Stage 4)')
param deployAfd bool = false

@description('Admin username for the jump VM')
param vmAdminUsername string = 'azureadmin'

@secure()
@description('Admin password for the jump VM')
param vmAdminPassword string

@description('AKS cluster DNS prefix')
param aksDnsPrefix string = 'pfaaa-aks'

// ─────────────────────────────────────────────
// Variables
// ─────────────────────────────────────────────
var uniqueSuffix = take(uniqueString(resourceGroup().id), 6)
var tags = {
  Environment: environmentName
  ManagedBy: 'Bicep'
  Project: projectName
  SecurityControl: 'Ignore'
}

// ─────────────────────────────────────────────
// Log Analytics (deployed first — referenced by all modules)
// ─────────────────────────────────────────────
module logAnalytics 'modules/loganalytics.bicep' = {
  name: 'loganalytics-deploy'
  params: {
    name: 'log-${projectName}-${environmentName}-${uniqueSuffix}'
    location: location
    tags: tags
  }
}

// ─────────────────────────────────────────────
// Networking
// ─────────────────────────────────────────────
module networking 'modules/networking.bicep' = {
  name: 'networking-deploy'
  params: {
    vnetName: 'vnet-${projectName}-${environmentName}'
    location: location
    tags: tags
    logAnalyticsWorkspaceName: logAnalytics.outputs.resourceName
  }
}

// ─────────────────────────────────────────────
// Azure Bastion
// ─────────────────────────────────────────────
module bastion 'modules/bastion.bicep' = {
  name: 'bastion-deploy'
  params: {
    name: 'bas-${projectName}-${environmentName}'
    location: location
    tags: tags
    bastionSubnetId: networking.outputs.bastionSubnetId
    logAnalyticsWorkspaceName: logAnalytics.outputs.resourceName
  }
}

// ─────────────────────────────────────────────
// Jump VM
// ─────────────────────────────────────────────
module jumpvm 'modules/jumpvm.bicep' = {
  name: 'jumpvm-deploy'
  params: {
    name: 'vm-jump-${environmentName}'
    location: location
    tags: tags
    subnetId: networking.outputs.vmSubnetId
    adminUsername: vmAdminUsername
    adminPassword: vmAdminPassword
    logAnalyticsWorkspaceName: logAnalytics.outputs.resourceName
  }
}

// ─────────────────────────────────────────────
// Key Vault
// ─────────────────────────────────────────────
module keyvault 'modules/keyvault.bicep' = {
  name: 'keyvault-deploy'
  params: {
    name: 'kv-${take(projectName,6)}-${take(environmentName,3)}-${uniqueSuffix}'
    location: location
    tags: tags
    privateEndpointSubnetId: networking.outputs.peSubnetId
    vnetId: networking.outputs.vnetId
    logAnalyticsWorkspaceName: logAnalytics.outputs.resourceName
  }
}

// ─────────────────────────────────────────────
// Azure Container Registry
// ─────────────────────────────────────────────
module acr 'modules/acr.bicep' = {
  name: 'acr-deploy'
  params: {
    name: 'cr${take(replace(projectName,'-',''),8)}${take(environmentName,3)}${uniqueSuffix}'
    location: location
    tags: tags
    privateEndpointSubnetId: networking.outputs.peSubnetId
    vnetId: networking.outputs.vnetId
    logAnalyticsWorkspaceName: logAnalytics.outputs.resourceName
  }
}

// ─────────────────────────────────────────────
// Azure AI Foundry Hub + Project
// ─────────────────────────────────────────────
module foundry 'modules/foundry.bicep' = {
  name: 'foundry-deploy'
  params: {
    hubName: 'aih-${projectName}-${environmentName}-${uniqueSuffix}'
    projectName: 'aip-${projectName}-${environmentName}'
    openAiName: 'oai-${projectName}-${environmentName}'
    location: location
    tags: tags
    privateEndpointSubnetId: networking.outputs.peSubnetId
    vnetId: networking.outputs.vnetId
    keyVaultId: keyvault.outputs.resourceId
    storageAccountName: 'st${take(replace(projectName, '-', ''),6)}${take(environmentName,3)}${uniqueSuffix}'
    logAnalyticsWorkspaceName: logAnalytics.outputs.resourceName
  }
}

// ─────────────────────────────────────────────
// AKS Private Cluster
// ─────────────────────────────────────────────
module aks 'modules/aks.bicep' = {
  name: 'aks-deploy'
  params: {
    name: 'aks-${projectName}-${environmentName}'
    location: location
    tags: tags
    dnsPrefix: aksDnsPrefix
    aksSubnetId: networking.outputs.aksSubnetId
    logAnalyticsWorkspaceName: logAnalytics.outputs.resourceName
  }
}

// ─────────────────────────────────────────────
// APIM
// ─────────────────────────────────────────────
module apim 'modules/apim.bicep' = {
  name: 'apim-deploy'
  params: {
    name: 'apim-${projectName}-${environmentName}-${uniqueSuffix}'
    location: location
    tags: tags
    virtualNetworkType: apimMode
    apimSubnetId: networking.outputs.apimSubnetId
    vnetId: networking.outputs.vnetId
    logAnalyticsWorkspaceName: logAnalytics.outputs.resourceName
  }
}

// ─────────────────────────────────────────────
// Azure Front Door (Stage 4 — conditional)
// ─────────────────────────────────────────────
module afd 'modules/afd.bicep' = if (deployAfd) {
  name: 'afd-deploy'
  params: {
    name: 'afd-${projectName}-${environmentName}'
    location: 'global'
    tags: tags
    apimPrivateLinkServiceId: apim.outputs.privateLinkServiceId
    logAnalyticsWorkspaceName: logAnalytics.outputs.resourceName
  }
}

// ─────────────────────────────────────────────
// RBAC: AKS Kubelet → ACR (AcrPull)
// ─────────────────────────────────────────────
module acrPullAssignment 'modules/roleassignment.bicep' = {
  name: 'acrpull-assign'
  params: {
    principalId: aks.outputs.kubeletIdentityObjectId
    roleDefinitionId: '7f951dda-4ed3-4680-a7ca-43fe172d538d' // AcrPull
    scopeResourceId: acr.outputs.resourceId
  }
}

// ─────────────────────────────────────────────
// RBAC: AKS Workload Identity → Foundry (Cognitive Services OpenAI User)
// ─────────────────────────────────────────────
module foundryRbac 'modules/roleassignment.bicep' = {
  name: 'foundry-rbac-assign'
  params: {
    principalId: aks.outputs.workloadIdentityPrincipalId
    roleDefinitionId: '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd' // Cognitive Services OpenAI User
    scopeResourceId: foundry.outputs.hubResourceId
  }
}

// ─────────────────────────────────────────────
// RBAC: AKS Workload Identity → OpenAI (Cognitive Services OpenAI User)
// ─────────────────────────────────────────────
module openAiRbac 'modules/roleassignment.bicep' = {
  name: 'openai-rbac-assign'
  params: {
    principalId: aks.outputs.workloadIdentityPrincipalId
    roleDefinitionId: '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd' // Cognitive Services OpenAI User
    scopeResourceId: foundry.outputs.openAiResourceId
  }
}

// ─────────────────────────────────────────────
// RBAC: AKS Workload Identity → Key Vault (Key Vault Secrets User)
// ─────────────────────────────────────────────
module kvRbac 'modules/roleassignment.bicep' = {
  name: 'kv-rbac-assign'
  params: {
    principalId: aks.outputs.workloadIdentityPrincipalId
    roleDefinitionId: '4633458b-17de-408a-b874-0445c86b69e6' // Key Vault Secrets User
    scopeResourceId: keyvault.outputs.resourceId
  }
}

// ─────────────────────────────────────────────
// Outputs
// ─────────────────────────────────────────────
output aksClusterName string = aks.outputs.resourceName
output acrLoginServer string = acr.outputs.loginServer
output apimGatewayUrl string = apim.outputs.gatewayUrl
output foundryProjectEndpoint string = foundry.outputs.projectEndpoint
output openAiEndpoint string = foundry.outputs.openAiEndpoint
output jumpVmName string = jumpvm.outputs.resourceName
output afdEndpointUrl string = deployAfd ? afd!.outputs.endpointUrl : ''
