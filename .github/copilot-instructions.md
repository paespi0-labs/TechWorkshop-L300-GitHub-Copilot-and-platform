# Copilot Instructions for ZavaStorefront Workshop

## Project Context

This is an L300 GitHub Copilot & Platform workshop repo. The app is a .NET 6 MVC storefront (ZavaStorefront) deployed to Azure via AZD with Docker containers. Infrastructure is Bicep, deployed with `azd up`.

## Azure Skills — Consult Before Architecture Decisions

Before generating GitHub issues, writing infrastructure requirements, or making hosting/service decisions, consult the `azure-prepare` skill. Ask it about service selection, Docker build strategies, and AZD compatibility before locking in constraints.

**Why:** During this workshop, the architecture was determined by the `/create-issue` prompt, not by the infrastructure code. Skills like `azure-prepare` have decision trees that surface trade-offs (e.g., ACR Tasks vs local Docker, App Service vs Container Apps) — but only if asked before requirements are written.

## AZD + Docker: Known Limitation

AZD does not support Docker build/push for `host: appservice`. It only supports Docker workflows natively when `host: containerapp`.

**Workaround for App Service + Docker:** Use AZD pre-deploy hooks with `az acr build` (ACR Tasks) to build in the cloud. This avoids requiring local Docker and keeps everything inside `azd up`.

```yaml
# Example: App Service with cloud-based Docker build
services:
  web:
    project: ./src
    language: dotnet
    host: appservice
    hooks:
      predeploy:
        shell: sh
        run: |
          az acr build --registry ${AZURE_CONTAINER_REGISTRY_NAME} \
            --image zava-storefront:latest ./src
```

**Do not** switch hosting platforms just because AZD's native Docker flow doesn't support the current host. Instead, extend AZD with hooks. Changing hosts should be a deliberate architecture decision, not a workaround for a toolchain limitation.

## Agent Behavior Preferences

- When hitting a toolchain limitation, prefer extending the tool (hooks, scripts) over changing the target architecture.
- When generating infrastructure issues, include explicit constraints about build location (local vs cloud), hosting target, and whether local Docker is available.
- Always surface trade-offs before making hosting decisions — don't silently switch from App Service to Container Apps.
- Redact API keys and secrets from any documentation files.

## Current Infrastructure

- **Hosting:** Azure Container Apps (Container Apps Environment + Container App)
- **Registry:** Azure Container Registry (Basic SKU, managed identity for pulls)
- **AI:** Azure AI Services with GPT-4o + Phi-4 serverless endpoint
- **IaC:** Bicep modules in `infra/` directory
- **Deploy:** `azd up` from the repo root
- **AZD env:** `dev`, region `westus3`
