# Private Foundry + AKS + APIM + AFD — Progressive Security Demo

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com)

A **4-stage progressive network-security tightening** demonstration for an AI chat workload hosted in Azure AI Foundry. Each stage increases isolation from direct AKS access through to full AFD + private APIM production architecture.

## Architecture

```
Stage 4 (Production):
Public User → Azure Front Door Premium → [Private Link] → APIM (Internal) → AKS LB (private) → .NET Chat App → [Private Endpoint] → Azure AI Foundry Chat Agent
```

Jump VM access: Bastion only (no public IP on VM).

## Demo Stages

| Stage | Mode          | How to trigger                          |
|-------|---------------|-----------------------------------------|
| 1     | Direct AKS LB | Connect to jump VM via Bastion          |
| 2     | APIM Public   | `APIM_MODE=External` (default)          |
| 3     | APIM Private  | `APIM_MODE=Internal` + `azd up`         |
| 4     | AFD + APIM    | `DEPLOY_AFD=true` + `azd up` + approve private link |

## Quick Start

### Prerequisites

- Azure CLI + `azd` CLI installed
- Azure subscription with sufficient quota for AKS, APIM Developer, AFD Premium

### Deploy

```bash
azd env new demo
azd env set AZURE_LOCATION eastus2
azd env set VM_ADMIN_PASSWORD "YourStrongPassword123!"

# Stage 2 (APIM public) — default
azd up

# Stage 3 (APIM private)
azd env set APIM_MODE Internal
azd up

# Stage 4 (AFD + private APIM)
azd env set DEPLOY_AFD true
azd up
# Then approve AFD private link in Azure Portal → APIM → Networking
```

### Tear Down

```bash
azd down --force --purge
```

> ⚠️ **Cost warning**: ~$800–900/month if left running. Always tear down after the demo.

## Resources Created

| Resource                 | Purpose                                   |
|--------------------------|-------------------------------------------|
| Azure AI Foundry Hub     | AI agent hosting (private)                |
| Azure AI Foundry Project | Chat agent project                        |
| Private AKS Cluster      | .NET chat app runtime                     |
| Azure Container Registry | Private container image registry          |
| Azure Bastion (Standard) | Secure VM access without public IP        |
| Windows Jump VM          | Admin access to private resources         |
| APIM (Developer SKU)     | API gateway with VNet injection           |
| Azure Front Door Premium | Public edge with private link to APIM     |
| Key Vault                | Secrets storage (private endpoint)        |
| Log Analytics            | Centralized diagnostics                   |
| VNet (6 subnets)         | Network isolation per tier                |

## Scenario Artifacts

| File                          | Description                          |
|-------------------------------|--------------------------------------|
| `01-requirements.md`          | Functional and network requirements  |
| `02-architecture-assessment.md` | SKU recommendations and ADRs       |
| `08-demo-guide.md`            | Step-by-step demo script             |
| `infra/main.bicep`            | Root Bicep template                  |
| `infra/modules/`              | Modular Bicep (networking, AKS, APIM, AFD, Foundry, ...) |
| `azure.yaml`                  | azd project definition               |
