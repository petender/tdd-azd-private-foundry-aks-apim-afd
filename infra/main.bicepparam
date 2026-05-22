using './main.bicep'

param environmentName = readEnvironmentVariable('AZURE_ENV_NAME', 'demo')
param location = readEnvironmentVariable('AZURE_LOCATION', 'eastus2')
param projectName = 'pfaaa'
param apimMode = readEnvironmentVariable('APIM_MODE', 'External')
param deployAfd = bool(readEnvironmentVariable('DEPLOY_AFD', 'false'))
param vmAdminUsername = readEnvironmentVariable('VM_ADMIN_USERNAME', 'azureadmin')
param vmAdminPassword = readEnvironmentVariable('VM_ADMIN_PASSWORD', '')
param aksDnsPrefix = 'pfaaa-aks'
