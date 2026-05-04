# Chat App — Build, Push & Deploy
#
# Prerequisites (run once from the jump VM):
#   az login
#   az aks get-credentials --resource-group rg-pfaaa-demo --name aks-pfaaa-pfaaa-demo
#
# Usage:
#   .\deploy-chatapp.ps1 -AcrName <acrLoginServer> -ResourceGroup rg-pfaaa-demo `
#       -AksName aks-pfaaa-pfaaa-demo -FoundryEndpoint <endpoint> [-AgentId <id>] [-WorkloadClientId <id>]

[CmdletBinding()]
param (
    [Parameter(Mandatory)]
    [string]$AcrName,

    [Parameter(Mandatory)]
    [string]$ResourceGroup,

    [Parameter(Mandatory)]
    [string]$AksName,

    [Parameter(Mandatory)]
    [string]$FoundryEndpoint,

    [string]$AgentId = "",
    [string]$WorkloadClientId = "",
    [string]$ImageTag = "latest"
)

$ErrorActionPreference = 'Stop'
$Image = "$AcrName/foundrychat:$ImageTag"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$SrcDir = Join-Path $ScriptDir "src/FoundryChat.Web"

Write-Host "`n==> Building Docker image: $Image" -ForegroundColor Cyan
az acr build --registry $AcrName --image "foundrychat:$ImageTag" $SrcDir --platform linux/amd64

Write-Host "`n==> Connecting to AKS" -ForegroundColor Cyan
az aks get-credentials --resource-group $ResourceGroup --name $AksName --overwrite-existing

Write-Host "`n==> Applying namespace + service account" -ForegroundColor Cyan
$saManifest = Get-Content "$ScriptDir/k8s/serviceaccount.yaml" -Raw
if ($WorkloadClientId) {
    $saManifest = $saManifest -replace "WORKLOAD_IDENTITY_CLIENT_ID_PLACEHOLDER", $WorkloadClientId
}
$saManifest | kubectl apply -f -

Write-Host "`n==> Creating/updating secret" -ForegroundColor Cyan
kubectl create secret generic chat-app-secrets `
    --namespace chat-app `
    --from-literal=FOUNDRY_PROJECT_ENDPOINT=$FoundryEndpoint `
    --from-literal=FOUNDRY_AGENT_ID=$AgentId `
    --dry-run=client -o yaml | kubectl apply -f -

Write-Host "`n==> Applying deployment" -ForegroundColor Cyan
$deployment = Get-Content "$ScriptDir/k8s/deployment.yaml" -Raw
$deployment = $deployment -replace "REGISTRY_PLACEHOLDER", $AcrName
$deployment | kubectl apply -f -

Write-Host "`n==> Applying service (internal LB)" -ForegroundColor Cyan
kubectl apply -f "$ScriptDir/k8s/service.yaml"

Write-Host "`n==> Waiting for rollout..." -ForegroundColor Cyan
kubectl rollout status deployment/chat-app -n chat-app --timeout=300s

Write-Host "`n==> Internal LB IP (may take 1-2 min to provision):" -ForegroundColor Cyan
kubectl get service chat-app -n chat-app

Write-Host "`n==> Done. Update APIM backend URL with the EXTERNAL-IP above." -ForegroundColor Green
