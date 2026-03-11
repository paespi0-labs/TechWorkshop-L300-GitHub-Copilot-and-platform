# Zava Architecture Diagrams

## 1. Current State Architecture

```mermaid
graph TD
    FD["Azure Front Door"] --> WA
    DNS["Azure DNS"] --> FD

    subgraph AppVNet["App VNet"]
        ASP["App Service Plan"]
        WA["Web App"]
        ASP --> WA
    end

    WA --> CDB
    CDB --> WA

    subgraph DBVNet["DB VNet"]
        CDB["Cosmos DB"]
    end

    subgraph Monitor["Observability"]
        AM["Azure Monitor"]
        LA["Log Analytics"]
        AM --> LA
    end

    WA --> AM
    CDB --> AM

    KV["Key Vault"] -.-> WA
    GH["GitHub"] -.-> WA
    EID["Entra ID"] -.-> WA

    subgraph Lakehouse["Microsoft Fabric — Lakehouse"]
        BRZ["Bronze Layer"]
        SIL["Silver Layer"]
        GLD["Gold Layer"]
        BRZ --> SIL --> GLD
    end
```

---

## 2. Target State — Agentic DevOps + AI Architecture

```mermaid
graph TD
    DEV["Developer"] -->|VS Code + Copilot extension| COP["GitHub Copilot"]
    DEV -->|GitHub.com| GHE["GitHub Enterprise"]

    COP -->|code gen, review, refactor| GHE
    GHE -->|CI/CD pipelines| GHA["GitHub Actions"]
    GHE -->|secret scanning, SAST, SCA| GHAS["GitHub Advanced Security"]

    GHA -->|deploy containers| ACR["Azure Container Registry"]
    ACR -->|AcrPull RBAC| APP["App Service<br/>(Linux Container)"]
    APP --> APPINS["Application Insights"]

    subgraph Foundry["Azure AI Foundry — westus3"]
        HUB["AI Hub"]
        PROJ["AI Project"]
        GPT4["GPT-4 deployment"]
        PHI["Phi deployment"]
        HUB --> PROJ
        PROJ --> GPT4
        PROJ --> PHI
    end

    APP -->|AI calls| HUB
    AGENT["AI Agents<br/>(code review, infra, monitoring)"] --> GHE
    AGENT --> HUB

    subgraph Lakehouse["Microsoft Fabric — Lakehouse (read-only)"]
        BRZ["Bronze"] --> SIL["Silver"] --> GLD["Gold"]
    end

    PROJ -->|read-only queries| BRZ
    KV["Key Vault"] -.->|secrets| APP
    KV -.->|secrets| GHA
    EID["Entra ID"] -.->|RBAC| APP
    EID -.->|RBAC| GHE
    EID -.->|RBAC| HUB
```

---

## 3. SDLC Whiteboard — GitHub Workflow Steps Across SDLC Phases

> Modeled after the L300 GitHub Copilot & Platform workshop whiteboard template.  
> Row order matches the template: Prepare → Harden → Connect to Azure → Develop → Create Landing Zone (infra track runs in parallel below).  
> Each active cell contains sticky notes: 📋 **Tasks**, 🔧 **Tools**, ☁️ **Resources**, ✅ **Governance/RAI checks**.  
> Inactive phases are marked `·`.  
> *PAF key action IDs from the [GHE Platform Adoption Kit](https://github.com/customer-success-microsoft/ghe-platform-adoption-kit).*

| **GitHub Step** | 📅 **Planning** | 🔍 **Analysis** | 🎨 **Design** | 💻 **Development** | 🧪 **Testing** | 🚀 **Deployment** | 🛠️ **Maintenance** |
|---|---|---|---|---|---|---|---|
| **📦 Prepare GitHub Environment**<br/>*Set up the DevOps toolset*<br/><sub>PAF: learn-design-and-plan-for-enterprise-onboarding · enterprise-account-setup · define-org-and-team-structure</sub> | 📋 Identify stakeholders (Tim, Lydia, Kian, Kadji)<br/>📋 Configure GitHub Enterprise license & seats<br/>📋 Draft spec, SDLC plan & README<br/>📋 Define objectives and success criteria<br/>📋 Define language standards: C#, JavaScript, or Python only<br/>🔧 GitHub Enterprise<br/>🔧 GitHub Projects (roadmap)<br/>🔧 GitHub Issues | 📋 Run GHCP in Agent mode to explore codebase<br/>📋 Install VS Code extensions<br/>📋 Configure MCP CLI & Azure tools<br/>📋 Identify tools, extensions, and integrations<br/>📋 Enable Copilot across all surfaces: IDE, CLI, GitHub Workspace<br/>📋 *(No AI engineers on staff — Copilot + AI Foundry abstractions bridge the gap)*<br/>🔧 Visual Studio Code (IDE)<br/>🔧 GitHub Copilot (IDE + CLI + github.com)<br/>🔧 MCP CLI<br/>☁️ Azure OAI/LLM, DB, Storage | 📋 Define org & team structure<br/>📋 Configure SSO/SAML via Entra ID<br/>📋 Set repo templates and CODEOWNERS<br/>📋 Configure Copilot custom instructions to enforce coding standards<br/>📋 Define Responsible AI (RAI) requirements<br/>✅ Governance review checklist<br/>🔧 GitHub Enterprise policies<br/>🔧 Entra ID (SAML/SCIM)<br/>🔧 GitHub Copilot | `·` | `·` | `·` | `·` |
| **🔒 Harden GitHub Environment**<br/>*Security, governance & compliance*<br/><sub>PAF: implement-scaled-governance · adopt-pull-request-reviews</sub> | `·` | 📋 Define branch protection & ruleset strategy<br/>📋 Plan Dependabot alert policy<br/>📋 Identify sensitive data & secret types<br/>📋 Define least-privilege scopes for AI agents (no write access to prod)<br/>🔧 GitHub Enterprise policies<br/>🔧 GitHub Issues (tracking) | 📋 Configure CODEOWNERS<br/>📋 Enable Dependabot & secret scanning<br/>📋 Define required status checks<br/>📋 Set environment protection rules & required reviewers<br/>📋 Scope agent permissions: read-only on Fabric Lakehouse, no OLTP access<br/>✅ Agent safety gates: validate discount offers, restrict data exposure<br/>🔧 GitHub Advanced Security<br/>🛡️ Entra ID, Key Vault | 📋 Enable GHAS code scanning on every PR<br/>📋 Enable push protection for secrets<br/>📋 Enforce signed commits<br/>📋 Adopt PR review & management strategy (address tech debt risk)<br/>📋 Require human review gate on all Copilot-generated code before merge<br/>🔧 GHAS (SAST, SCA)<br/>🔧 GitHub Actions | 📋 Validate all security gates pass<br/>📋 Run Responsible AI compliance checklist<br/>📋 Governance sign-off<br/>📋 Verify agent cannot expose internal sales data to customers<br/>✅ Test Document reviewed<br/>🔧 GHAS dashboards<br/>🔧 Dependabot | `·` | `·` |
| **🔗 Connect GitHub to Azure**<br/>*Create a CI/CD workflow*<br/><sub>PAF: optimize-system-integrations-workflows</sub> | `·` | `·` | `·` | 📋 Create GitHub Actions build workflow<br/>📋 Configure OIDC federated identity (no long-lived secrets)<br/>📋 Use ACR Tasks to build image — no local Docker required<br/>📋 GHCP generates workflow YAML<br/>🔧 GitHub Actions<br/>🔧 Azure OIDC federation<br/>🔧 GitHub Copilot | 📋 Test CI pipeline end-to-end<br/>📋 Validate ACR image build succeeds<br/>📋 Confirm OIDC auth works<br/>📋 Validate environment secrets correctly scoped<br/>🔧 GitHub Actions<br/>🔧 ACR Tasks | 📋 Run full CD pipeline on merge to main<br/>📋 Deploy container to App Service<br/>📋 Verify App Service pulls from ACR via Managed Identity (AcrPull RBAC)<br/>📋 Confirm Application Insights telemetry flowing<br/>📋 Track DORA metrics (deployment frequency, lead time)<br/>🔧 GitHub Actions<br/>🔧 Azure RBAC (AcrPull)<br/>🔧 Application Insights | 📋 AI Agents automate ops monitoring & alerting<br/>📋 Dependabot keeps dependencies current<br/>📋 Copilot assists with triage, patch, refactor<br/>📋 Measure developer productivity & engagement<br/>📋 Share success stories with stakeholders (Lydia, Kian)<br/>🔧 Dependabot<br/>🔧 GitHub Actions<br/>🔧 AI Agents (ops automation)<br/>🔧 Azure Monitor, Log Analytics |
| **✨ Develop: Add Features**<br/>*Create new functionality & update existing features*<br/><sub>PAF: developer-learning-and-training · adopt-pull-request-reviews · drive-innersource-adoption</sub> | `·` | `·` | `·` | 📋 Write all code in C#, JavaScript, or Python only<br/>📋 Implement AI interior design assistant chat UI<br/>📋 Integrate Azure AI Foundry SDK — abstract model calls to avoid vendor lock-in<br/>📋 Migrate ZavaStorefront .NET 6 → .NET 8<br/>📋 Connect agents to Fabric Lakehouse (read-only, bronze/silver/gold tiers)<br/>📋 Implement content safety & guardrails on customer-facing AI agent<br/>📋 Add discount-offer validation: agent cannot issue unauthorized discounts<br/>📋 Code review & refactor with GitHub Copilot — require senior engineer sign-off<br/>📋 Use Copilot custom instructions to enforce team coding standards<br/>📋 *(Tech debt mitigation: Copilot generates drafts; humans own understanding & approval)*<br/>🔧 VS Code + GitHub Copilot (IDE, CLI, Workspace)<br/>🔧 GitHub Codespaces<br/>🔧 GitHub Issues + Projects<br/>☁️ Microsoft Fabric Lakehouse (read-only)<br/>☁️ Azure AI Foundry SDK | 📋 Copilot-assisted unit & integration test generation<br/>📋 GHAS code scan on every PR<br/>📋 Dependabot SCA check<br/>📋 Validate AI agent responses against RAI guidelines<br/>📋 Test content safety filters on customer chat agent<br/>📋 Verify Fabric Lakehouse queries return no raw OLTP/sales data to customers<br/>✅ No AI model lock-in: all model calls go through AI Foundry abstraction layer<br/>🔧 GitHub Actions CI<br/>🔧 GHAS, Dependabot | `·` | `·` |
| **☁️ Create Azure Landing Zone**<br/>*Configure the Azure resources you need*<br/>*(infra track — runs in parallel with Develop)*<br/><sub>PAF: enterprise-account-setup · configure-iam</sub> | `·` | `·` | 📋 Design resource topology & naming convention<br/>📋 Author Bicep modules: ACR, App Service Plan, App Service, AI Foundry Hub + Project, Application Insights<br/>📋 Define Managed Identity & AcrPull RBAC strategy (no ACR admin user)<br/>📋 Define azure.yaml for AZD<br/>📋 Plan GPT-4 + Phi model deployments in westus3<br/>🔧 AZD CLI<br/>🔧 Bicep in VS Code<br/>🔧 Docker extension in VS Code<br/>🔧 GitHub Copilot (infra scaffolding) | 📋 Provision resource group in westus3<br/>📋 Run `azd provision` dry-run & validate<br/>📋 Wire `APPLICATIONINSIGHTS_CONNECTION_STRING` app setting<br/>📋 Configure AI Foundry Hub + Project + model deployments<br/>📋 GHCP Agent generates subscription info & resource configs<br/>☁️ ACR (admin disabled, AcrPull via Managed Identity)<br/>☁️ App Service Plan (Linux)<br/>☁️ Azure AI Foundry (GPT-4, Phi — westus3)<br/>☁️ Application Insights<br/>🔧 AZD CLI, Azure CLI | 📋 Validate Bicep with `az deployment validate`<br/>📋 Confirm all RBAC role assignments<br/>📋 Test Managed Identity pull from ACR<br/>📋 Verify AI Foundry model endpoints respond<br/>🔧 AZD CLI<br/>🔧 Azure Portal | 📋 Run `azd up` (full deploy to westus3)<br/>📋 Verify all resources in single resource group<br/>📋 Confirm App Insights live telemetry<br/>📋 Confirm GPT-4 and Phi accessible from App Service<br/>🔧 AZD CLI<br/>🔧 GitHub Actions | `·` |

---

### Zava Objections → Whiteboard Response Mapping

| Zava Objection | Where It's Addressed |
|---|---|
| *"We have no AI engineers"* | Prepare — Copilot + AI Foundry SDK bridges the skills gap; Develop — team uses SDK abstractions, not raw model APIs |
| *"Don't want model lock-in"* | Develop — AI Foundry SDK abstraction layer; swap GPT-4 ↔ Phi or other models without code changes |
| *"LLMs saying inappropriate things"* | Harden — content safety gates & RAI checklist; Develop — content safety filters on customer agent |
| *"Agents deleting prod data or exposing internal data"* | Harden — agent least-privilege scopes, read-only Lakehouse access, no OLTP; Harden — discount-offer validation gates |
| *"Copilot generates code that increases technical debt"* | Harden — mandatory human review gate on Copilot-generated PRs; Prepare — Copilot custom instructions enforce standards |
| *"Code generation doesn't follow best practices"* | Prepare — Copilot custom instructions; Harden — PR review strategy + senior engineer sign-off required |

---

### Stakeholder → SDLC Step Mapping

| Stakeholder | Role | Primary SDLC Concern | Relevant Steps |
|---|---|---|---|
| **Lydia Bauer** | Enterprise IT Architect | Agentic DevOps, deployment agility | Prepare, Connect to Azure, Create Landing Zone |
| **Kian Lambert** | App Development Manager | Developer productivity, .NET migration, avoiding technical debt | Prepare, Harden, Develop |
| **Kadji Bell** | CISO / Platform Ops | Security automation, reduced monitoring burden, agent safety | Harden, Connect to Azure (Maintenance) |
| **Tim de Boer** | Marketing Manager | Customer AI agent, internal data analysis, access controls | Develop, Create Landing Zone |
