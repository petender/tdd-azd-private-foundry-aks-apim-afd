// Log Analytics Workspace module

param name string
param location string
param tags object

module workspace 'br/public:avm/res/operational-insights/workspace:0.9.0' = {
  name: '${name}-deploy'
  params: {
    name: name
    location: location
    tags: tags
    skuName: 'PerGB2018'
    dataRetention: 30
    dailyQuotaGb: 5
  }
}

output resourceId string = workspace.outputs.resourceId
output resourceName string = workspace.outputs.name
