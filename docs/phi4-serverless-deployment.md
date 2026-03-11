# Deploying Phi-4 as a Serverless Endpoint on Azure — Full Runbook

> **Author:** Pedro Espinoza (with GitHub Copilot agent mode)  
> **Date:** March 10, 2026  
> **Environment:** Azure subscription `ME-MngEnvMCAP990526-pespinoza-1`, region `westus3`  
> **Purpose:** Document every attempt, failure, and lesson learned while deploying Microsoft Phi-4 as a serverless endpoint — so peers can skip the dead ends and go straight to what works.

---

## Table of Contents

- [Background](#background)
- [Attempt 1: Bicep via CognitiveServices Account](#attempt-1-bicep-via-cognitiveservices-account)
- [Attempt 2: MCP Foundry Tool (foundry\_models\_deploy)](#attempt-2-mcp-foundry-tool-foundry_models_deploy)
- [Side Quest: PublicNetworkAccess Blocked by Policy](#side-quest-publicnetworkaccess-blocked-by-policy)
- [Attempt 3: az ml serverless-endpoint create (SUCCESS)](#attempt-3-az-ml-serverless-endpoint-create-success)
- [Verification](#verification)
- [Current Status](#current-status)
- [Key Takeaways](#key-takeaways)
- [Reference Commands](#reference-commands)

---

## Background

Our infrastructure includes an **Azure AI Hub** and **AI Project** (Azure Machine Learning workspaces) along with an **Azure AI Services** (CognitiveServices) account. GPT-4o was already deployed on the CognitiveServices account via Bicep with no issues — it's an OpenAI-format model and that's the native deployment path for those.

Phi-4 is different. It's a **Microsoft-format** model (not OpenAI-format), and that distinction drives everything that went wrong and everything that ultimately worked.

### The Two "Airports" Mental Model

Think of Azure AI as having two airports in the same city:

| "Airport" | API Surface | Supports |
|---|---|---|
| **Azure AI Services** (CognitiveServices) | `Microsoft.CognitiveServices/accounts/deployments` | OpenAI-format models only (GPT-4o, DALL-E, Whisper, etc.) |
| **ML Workspace Serverless Endpoints** | `Microsoft.MachineLearningServices/workspaces/serverlessEndpoints` | Microsoft, Meta, Mistral, Cohere, and other model providers |

Phi-4 can only fly from the second airport. Every failed attempt below was us trying to board at the wrong terminal.

---

## Attempt 1: Bicep via CognitiveServices Account

### What We Tried

We initially included Phi-4 as a Bicep deployment in our `ai.bicep` module alongside GPT-4o, targeting the same Azure AI Services (CognitiveServices) account:

```bicep
resource phi4Deployment 'Microsoft.CognitiveServices/accounts/deployments@2024-10-01' = {
  parent: aiServicesAccount
  name: 'phi-4'
  sku: {
    name: 'GlobalStandard'
    capacity: 1
  }
  properties: {
    model: {
      format: 'Microsoft'
      name: 'Phi-4'
    }
  }
}
```

### What Happened

Bicep compilation succeeded (it's syntactically valid), but deployment would fail because **CognitiveServices account deployments do not support Microsoft-format models**. The API only accepts `format: 'OpenAI'`.

### How We Figured It Out

- The Azure REST API spec for `Microsoft.CognitiveServices/accounts/deployments` only documents OpenAI-format model deployments.
- The AI Foundry model catalog lists Phi-4 with `deployment_options: { serverless_endpoint: true, managed_compute: true }` — notably, **no** `cognitive_services` or `standard` deployment option.
- Azure documentation confirms: serverless API (pay-per-token) endpoints for non-OpenAI models are deployed through ML workspaces, not CognitiveServices accounts.

### Resolution

Removed the Phi-4 deployment from `ai.bicep`. Added a comment noting it must be deployed via AI Foundry portal or CLI. This was the correct call — Bicep cannot deploy serverless endpoints to ML workspaces (there is no Bicep resource type for `serverlessEndpoints` under `Microsoft.MachineLearningServices`).

**Source:** [Azure AI Services REST API - Deployments](https://learn.microsoft.com/en-us/rest/api/aiservices/accountdeployments/create-or-update) — only documents OpenAI model format.

---

## Attempt 2: MCP Foundry Tool (foundry_models_deploy)

### What We Tried

Used the Azure MCP Foundry server's `foundry_models_deploy` tool from within GitHub Copilot agent mode. First, we verified Phi-4 was available:

```
Tool: foundry_models_list
Input: model-name: "Phi-4"
Result: ✅ Found — deployment_options: { serverless_endpoint: true, managed_compute: true, free_playground: true }
```

Then attempted deployment:

```
Tool: foundry_models_deploy
Input:
  model-name: "Phi-4"
  deployment-name: "phi-4"
  resource-group: "rg-dev"
  project-name: "azprjobisfjfkji5x6"
```

### What Happened

**Failed** with error:

```
DeploymentModelNotSupported:
The model 'Format:Microsoft,Name:Phi-4' of account deployment is not supported.
```

### Why It Failed

The MCP `foundry_models_deploy` tool **deploys to Azure AI Services (CognitiveServices) accounts**, not to ML workspace serverless endpoints. Under the hood, it calls the `Microsoft.CognitiveServices/accounts/deployments` API — the exact same API we tried in Bicep. Same airport, same rejection.

This is a current limitation of the MCP Foundry tool. It works perfectly for OpenAI-format models (GPT-4o, etc.) but cannot deploy Microsoft/Meta/Mistral-format models that require the ML workspace serverless endpoint path.

### How We Confirmed

The error message `Format:Microsoft,Name:Phi-4 of account deployment is not supported` explicitly states it's trying an "account deployment" (CognitiveServices). The word "account" is the giveaway — ML workspace deployments are called "serverless endpoints," not "account deployments."

---

## Side Quest: PublicNetworkAccess Blocked by Policy

Before we could even attempt deployment via the AI Foundry portal, we hit a blocker: the portal showed `PublicNetworkAccessDisabled`.

### The Problem

Both the AI Hub (`azhubobisfjfkji5x6`) and AI Project (`azprjobisfjfkji5x6`) had `publicNetworkAccess: Disabled`, despite our Bicep explicitly setting `Enabled`:

```bash
# Checked via REST API
az rest --method get \
  --url "https://management.azure.com/subscriptions/{sub}/resourceGroups/rg-dev/providers/Microsoft.MachineLearningServices/workspaces?api-version=2024-10-01" \
  --query "value[].{name:name, kind:kind, publicNetworkAccess:properties.publicNetworkAccess}" \
  -o table

# Result:
# Name                Kind     PublicNetworkAccess
# azhubobisfjfkji5x6  Hub      Disabled
# azprjobisfjfkji5x6  Project  Disabled
```

### Root Cause: Azure Policy at Management Group Level

A policy called **`MCAPSGovDeployPolicies`** (aka "MCAPSGov Deploy and Modify Policies") was assigned at the management group level:

```
Scope: /providers/Microsoft.Management/managementGroups/32c515bf-8bf4-4d47-84e2-b5506a7329f3
```

This policy uses a **DeployIfNotExists** or **Modify** effect to automatically set `publicNetworkAccess: Disabled` on Machine Learning workspaces after they're created or updated. Our Bicep would set `Enabled`, then the policy would flip it to `Disabled` within minutes.

### How We Found It

```bash
# Listed policies with scope information
az policy assignment list --disable-scope-strict-match \
  --query "[?contains(displayName, 'MCAPSGov')].{name:name, displayName:displayName, scope:scope}" \
  -o table
```

### The Fix: Policy Exemption

We created a **policy exemption** scoped to our resource group so the MCAPSGov policy would stop overriding our setting:

```bash
MSYS_NO_PATHCONV=1 az policy exemption create \
  --name "rg-dev-ml-public-access" \
  --policy-assignment "/providers/Microsoft.Management/managementGroups/32c515bf-8bf4-4d47-84e2-b5506a7329f3/providers/Microsoft.Authorization/policyAssignments/MCAPSGovDeployPolicies" \
  --scope "/subscriptions/5734f8d9-881b-4d80-96d3-abd833647290/resourceGroups/rg-dev" \
  --exemption-category "Waiver" \
  --display-name "Allow public access for ML workspaces in rg-dev"
```

Then re-applied the setting:

```bash
az ml workspace update --name azhubobisfjfkji5x6 --resource-group rg-dev --public-network-access Enabled
az ml workspace update --name azprjobisfjfkji5x6 --resource-group rg-dev --public-network-access Enabled
```

### Verified

```bash
az rest --method get \
  --url "https://management.azure.com/subscriptions/{sub}/resourceGroups/rg-dev/providers/Microsoft.MachineLearningServices/workspaces?api-version=2024-10-01" \
  --query "value[].{name:name, publicNetworkAccess:properties.publicNetworkAccess}" \
  -o table

# Result:
# Name                PublicNetworkAccess
# azhubobisfjfkji5x6  Enabled ✅
# azprjobisfjfkji5x6  Enabled ✅
```

### Important Note for Peers

If you're in a managed environment (MCAPS, corporate tenant, lab subscription), always check for policy assignments before assuming your Bicep/Terraform settings will stick. The `MCAPSGovDeployPolicies` policy is common in Microsoft-managed subscriptions and silently overrides network access settings. The exemption has no expiry date, but if you re-provision the resource group from scratch, you'll need to recreate it.

**Prerequisite:** The `az ml` CLI extension must be installed:

```bash
az extension add --name ml --yes
```

---

## Attempt 3: az ml serverless-endpoint create (SUCCESS)

### What We Tried

Used the Azure ML CLI extension's `serverless-endpoint` command group (preview) to deploy Phi-4 directly to the ML workspace.

**Step 1: Create a YAML spec file**

```yaml
# phi4-endpoint.yml
name: phi-4-endpoint
model_id: azureml://registries/azureml/models/Phi-4
auth_mode: key
```

Key details about the YAML:
- `model_id` uses the `azureml://registries/azureml/models/Phi-4` format — this references the model from the Azure ML model registry (the public `azureml` registry, not a private one).
- No version specified — serverless endpoints always use the latest available version.
- `auth_mode: key` means the endpoint is secured with API keys (not AAD tokens).

**Step 2: Deploy**

```bash
MSYS_NO_PATHCONV=1 az ml serverless-endpoint create \
  --file "C:\Users\pespinoza\phi4-endpoint.yml" \
  --resource-group rg-dev \
  --workspace-name azprjobisfjfkji5x6
```

> **Git Bash gotcha:** The `az` CLI is a Windows Python process. Git Bash's POSIX path resolution (`/c/Users/...`) is not recognized by `az`. You must use Windows-style paths (`C:\Users\...`) for the `--file` argument, and prefix the command with `MSYS_NO_PATHCONV=1` to prevent Git Bash from mangling paths in other arguments (like Azure resource IDs that start with `/`).

### What Happened

```json
{
  "id": "/subscriptions/5734f8d9-881b-4d80-96d3-abd833647290/resourceGroups/rg-dev/providers/Microsoft.MachineLearningServices/workspaces/azprjobisfjfkji5x6/serverlessEndpoints/phi-4-endpoint",
  "location": "westus3",
  "model_id": "azureml://registries/azureml/models/Phi-4",
  "name": "phi-4-endpoint",
  "provisioning_state": "succeeded",
  "scoring_uri": "https://phi-4-endpoint.westus3.models.ai.azure.com"
}
```

**Provisioning state: succeeded.** Deployed in seconds.

### Why This Worked

This command talks to the **`Microsoft.MachineLearningServices` API**, specifically the `serverlessEndpoints` resource type. This is the correct deployment path for Microsoft-format models like Phi-4. Unlike CognitiveServices account deployments, this API supports the full model catalog (Microsoft, Meta, Mistral, Cohere, etc.).

**Source:** [Azure ML CLI serverless-endpoint reference](https://learn.microsoft.com/en-us/cli/azure/ml/serverless-endpoint)

---

## Verification

### Retrieved API Credentials

```bash
MSYS_NO_PATHCONV=1 az ml serverless-endpoint get-credentials \
  --name phi-4-endpoint \
  --resource-group rg-dev \
  --workspace-name azprjobisfjfkji5x6
```

```json
{
  "primaryKey": "<REDACTED>",
  "secondaryKey": "<REDACTED>"
}
```

### Live Test

```bash
curl -X POST "https://phi-4-endpoint.westus3.models.ai.azure.com/chat/completions" \
  -H "Authorization: Bearer <YOUR_PRIMARY_KEY>" \
  -H "Content-Type: application/json" \
  -d '{"messages":[{"role":"user","content":"What is the capital of France?"}],"max_tokens":100}'
```

Expected: A JSON response with Phi-4's answer. The endpoint uses the **Azure AI Model Inference API** (OpenAI-compatible chat completions format).

---

## Current Status

As of **March 10, 2026**:

| Resource | Status | Details |
|---|---|---|
| **Phi-4 Serverless Endpoint** | ✅ Live | `https://phi-4-endpoint.westus3.models.ai.azure.com` |
| **GPT-4o (CognitiveServices)** | ✅ Live | Deployed via Bicep on AI Services account |
| **AI Hub** | ✅ Public access enabled | Policy exemption in place |
| **AI Project** | ✅ Public access enabled | Policy exemption in place |
| **AI Foundry Portal** | ✅ Accessible | `https://ai.azure.com` |
| **Policy Exemption** | ✅ Active | `rg-dev-ml-public-access` — no expiry |
| **Container App (web)** | ✅ Live | `https://azappobisfjfkji5x6.greenrock-22f870f4.westus3.azurecontainerapps.io/` |

### Deployed Models Summary

| Model | Format | Deployment Type | API Endpoint |
|---|---|---|---|
| GPT-4o (`2024-08-06`) | OpenAI | CognitiveServices account deployment (Bicep) | Via AI Services account |
| Phi-4 | Microsoft | ML Workspace serverless endpoint (CLI) | `https://phi-4-endpoint.westus3.models.ai.azure.com` |

---

## Key Takeaways

1. **Model format determines deployment path.** OpenAI-format → CognitiveServices. Microsoft/Meta/Mistral-format → ML workspace serverless endpoints. There is no crossover.

2. **Bicep cannot deploy serverless endpoints.** There is no `Microsoft.MachineLearningServices/workspaces/serverlessEndpoints` Bicep resource type as of March 2026. You must use CLI, SDK, REST API, or the AI Foundry portal.

3. **The MCP Foundry tool has a blind spot.** `foundry_models_deploy` targets CognitiveServices accounts only. It works for GPT-4o but fails for Phi-4. If you're using Copilot agent mode, use terminal commands instead.

4. **Corporate policies silently override your IaC.** The `MCAPSGovDeployPolicies` policy flips `publicNetworkAccess` to `Disabled` on ML workspaces. Your Bicep says `Enabled` but the policy wins. You need a policy exemption before the setting sticks.

5. **Git Bash + Azure CLI = path headaches.** Always use `MSYS_NO_PATHCONV=1` as a prefix and Windows-style paths for `--file` arguments. Git Bash converts `/subscriptions/...` into `C:\subscriptions\...` without the prefix.

6. **Serverless = pay-per-token.** No reserved capacity, no SKU to size. You're billed per token consumed. Good for dev/test and bursty workloads.

---

## Reference Commands

### Deploy a new serverless endpoint

```bash
# 1. Install the ML CLI extension (one-time)
az extension add --name ml --yes

# 2. Create the endpoint YAML
cat > phi4-endpoint.yml << 'EOF'
name: phi-4-endpoint
model_id: azureml://registries/azureml/models/Phi-4
auth_mode: key
EOF

# 3. Deploy (use Windows path for --file in Git Bash)
MSYS_NO_PATHCONV=1 az ml serverless-endpoint create \
  --file "C:\Users\<you>\phi4-endpoint.yml" \
  --resource-group <your-rg> \
  --workspace-name <your-ai-project>

# 4. Get credentials
MSYS_NO_PATHCONV=1 az ml serverless-endpoint get-credentials \
  --name phi-4-endpoint \
  --resource-group <your-rg> \
  --workspace-name <your-ai-project>
```

### Fix PublicNetworkAccess if blocked by policy

```bash
# 1. Find the offending policy
az policy assignment list --disable-scope-strict-match \
  --query "[?contains(displayName, 'MCAPSGov')].{name:name, scope:scope}" -o table

# 2. Create an exemption for your RG
MSYS_NO_PATHCONV=1 az policy exemption create \
  --name "<rg>-ml-public-access" \
  --policy-assignment "<policy-assignment-id-from-step1>" \
  --scope "/subscriptions/<sub-id>/resourceGroups/<rg>" \
  --exemption-category "Waiver"

# 3. Re-enable public access
az ml workspace update --name <hub-name> --resource-group <rg> --public-network-access Enabled
az ml workspace update --name <project-name> --resource-group <rg> --public-network-access Enabled
```

### List and delete serverless endpoints

```bash
# List
MSYS_NO_PATHCONV=1 az ml serverless-endpoint list \
  --resource-group <rg> --workspace-name <project> -o table

# Delete
MSYS_NO_PATHCONV=1 az ml serverless-endpoint delete \
  --name phi-4-endpoint \
  --resource-group <rg> --workspace-name <project> --yes
```
