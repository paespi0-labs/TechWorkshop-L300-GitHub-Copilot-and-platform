# Docker Deployment: Container Apps vs App Service — How One Sentence in an Issue Prompt Changed the Entire Architecture

> **Author:** Pedro Espinoza (with GitHub Copilot agent mode)  
> **Date:** March 10, 2026  
> **Context:** During the L300 workshop, a peer and I both deployed the same Dockerized .NET app to Azure — but ended up with completely different architectures. After comparing notes, we traced the divergence back to a single sentence in the prompt used to create the GitHub issue.  
> **Updated:** Root cause identified — the peer's `/create-issue` prompt included "I don't want to install docker on my local machine." That one constraint changed everything downstream.

---

## The Root Cause: Different Prompts Created Different Issues

We initially assumed both agents were solving the same problem. They weren't. The divergence started at issue creation time — before any agent wrote a single line of infrastructure code.

### The Peer's Issue-Creation Prompt

The peer used this prompt with `/create-issue`:

> Provision Azure infrastructure for the ZavaStorefront web application. It will need a Linux App Service, and I want to use Docker to deploy to the App Service, so I'll need a Container Registry as well. **But I don't want to install docker on my local machine.** The AppService should use Azure RBAC to pull images not passwords.

That bolded sentence — "I don't want to install docker on my local machine" — is what drove their entire architecture. Copilot generated a GitHub issue with explicit requirements: no local Docker, use ACR Tasks, App Service with RBAC. Their coding agent then faithfully solved those constraints using a pre-deploy hook + ACR Tasks.

### Our Issue (Presumably Different)

Our issue didn't include the "no local Docker" constraint.  Without that constraint, our coding agent had no reason to avoid local Docker builds. When it hit the AZD limitation (`host: appservice` doesn't support Docker build/push), it took the path of least resistance — switch to Container Apps, where AZD handles Docker natively. Perfectly reasonable given the constraints it was given.

### The Cascade

```
Prompt sentence: "I don't want to install docker locally"
  └─› Issue requirement: "No Docker Desktop required"
      └─› Agent constraint: Can't use AZD native Docker (requires local Docker)
          └─› Agent solution: ACR Tasks + pre-deploy hook
              └─› Architecture: App Service + ACR Tasks + AZD hooks

Prompt: (no local-Docker constraint)
  └─› Issue: (no such requirement)
      └─› Agent: AZD native Docker is fine
          └─› Agent solution: Switch to Container Apps (AZD's native Docker path)
              └─› Architecture: Container Apps + local Docker build
```

The architecture was determined at prompt time, not at coding time.

---

## The Conflicting Workshop Requirements (Side Note)

Adding to the confusion, the workshop itself has contradictory guidance:

| Source | Says |
|---|---|
| Workshop prerequisites | Install Docker Desktop locally |
| Peer's GitHub issue | No local Docker required |
| Both issues | Use AZD for orchestration |

The workshop prereqs assume local Docker. The peer's prompt explicitly rejected that. AZD's native Docker support requires local Docker. These three are in tension, and different prompts resolve the tension differently. The workshop repo should probably clarify which constraint takes priority.

---

## What the Peer's Issue Required

The peer's issue (generated from their prompt) was specific about how the Docker build and hosting should work:

1. **No local Docker required.** "Image builds must happen in the cloud (ACR Tasks or CI/CD). Do not require Docker Desktop on the developer machine." This was also an explicit acceptance criterion: "No Docker Desktop required on the developer machine to build or deploy."

2. **App Service hosting.** The issue specified a "Linux App Service Plan" and "App Service (Linux, Container)" — not Container Apps.

3. **RBAC for image pulls.** "App Service must use a system-assigned or user-assigned Managed Identity with the AcrPull role on ACR. Admin user on ACR should remain disabled."

4. **Single azd up.** "azd up completes successfully in a clean subscription with no manual steps."

---

## How We Deviated From the Peer's Requirements (But Not Necessarily From Ours)

Compared to the peer's issue, our agent deviated. But it may have been faithful to our own issue's constraints (which likely didn't include the no-local-Docker requirement):

| Requirement | What Issue #1 Said | What We Did |
|---|---|---|
| Hosting | App Service (Linux, Container) | Container Apps |
| Docker build | Cloud-based (ACR Tasks), no local Docker | Local Docker build via AZD |
| RBAC image pulls | Managed Identity + AcrPull role | Managed Identity (met this one) |
| Single azd up | Yes | Yes (met this one) |

A peer's Copilot agent found a solution that met all four of their requirements. The difference wasn't agent quality — it was that their issue included constraints ours didn't, which forced their agent to find a more creative solution.

---

## What Happened: The AZD Limitation

When we set `host: appservice` in azure.yaml with a Dockerfile, AZD failed during deploy. AZD does not support Docker build/push for App Service targets. It only supports Docker workflows when `host: containerapp`.

This is a known AZD limitation, confirmed in GitHub issue Azure/azure-dev#2646. The AZD team has not implemented Docker build/push support for the App Service host type.

We had two choices:

1. Switch to Container Apps so AZD handles everything end-to-end
2. Stay on App Service and use AZD's hook system to handle the Docker build/push step

We chose option 1. A peer's Copilot agent chose option 2. Both work as deployments. Option 2 meets the peer's issue requirements (App Service, no local Docker). Our option met our issue's constraints (which didn't prohibit local Docker).

---

## Our Path: AZD + Container Apps

How it works:

- azure.yaml declares `host: containerapp` and `docker: path: ./Dockerfile`
- `azd up` (or `azd deploy`) builds the Docker image locally, pushes it to ACR, and configures the Container App to pull from ACR
- Single command, fully managed by AZD
- No manual steps, no extra scripting

What we deployed:

- Container Apps Environment with Log Analytics integration
- Container App with external ingress on port 80
- ACR with managed identity for pull access
- AZD handles image tagging, push, and container app revision updates on every deploy

Key config in azure.yaml:

```yaml
name: zava-storefront
services:
  web:
    project: ./src
    host: containerapp
    language: csharp
    docker:
      path: ./Dockerfile
```

Key output in main.bicep (this is what tells AZD to do Docker build/push):

```bicep
output AZURE_CONTAINER_REGISTRY_ENDPOINT string = acr.outputs.loginServer
```

Without that output, AZD won't know to build/push Docker images even with `host: containerapp`.

---

## The Alternative Path: AZD Pre-Deploy Hook + ACR Tasks + App Service

A peer worked around the AZD limitation without leaving AZD. Their Copilot agent generated a pre-deploy hook that teaches AZD how to build Docker images for App Service. This is the key insight we missed: AZD has a hook system that lets you inject custom steps into its lifecycle.

### How AZD Hooks Work

AZD supports lifecycle hooks defined in azure.yaml. You can run scripts at specific points:

- `preprovision` — before Bicep/Terraform runs
- `postprovision` — after infrastructure is created
- `predeploy` — before the app is deployed
- `postdeploy` — after deploy completes

Hooks can be inline scripts or external shell/PowerShell files. They run in the same authenticated context as AZD, so they have access to Azure CLI and all AZD environment variables.

### What the Peer's Copilot Agent Generated

Their azure.yaml kept `host: appservice` but added a pre-deploy hook:

```yaml
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

(The exact hook script may vary — the point is that `az acr build` runs as a pre-deploy step inside AZD's lifecycle.)

### The Flow

1. User runs `azd up`
2. AZD provisions infrastructure via Bicep (App Service Plan, Web App configured as Linux container, ACR)
3. Pre-deploy hook fires and runs `az acr build` — this uploads the source code to ACR and builds the Docker image in the cloud (no local Docker engine needed)
4. AZD deploys by configuring the App Service to pull the newly built image from ACR
5. App is live

Single command. Same `azd up` experience. App Service as the host. Docker image built in the cloud.

### Why This Is Clever

The peer's Copilot agent recognized the AZD limitation and generated the workaround automatically. Instead of switching the hosting platform, it extended AZD's capabilities with a hook. This is arguably more elegant because:

- No local Docker engine required (ACR Tasks builds in the cloud)
- App Service is a simpler, more familiar hosting model
- Still a single `azd up` command
- The hook is declarative and version-controlled in azure.yaml

### What Our Agent Did Differently

Our Copilot agent took a different approach — it switched the hosting platform to Container Apps, which has native AZD Docker support. This avoided the need for hooks but changed the infrastructure. Neither approach is wrong; they represent different strategies for solving the same problem.

The fact that two Copilot agents, working independently on the same workshop but with different issue prompts, found two completely different architectures is the key lesson here. The agents were both competent — they just had different inputs.

---

## Comparison

| Dimension | AZD + Container Apps (our path) | AZD Hook + ACR Tasks + App Service (peer's path) |
|---|---|---|
| Deploy command | `azd up` (one command) | `azd up` (one command, hook runs automatically) |
| Build location | Local Docker engine | Cloud (ACR Tasks, no local Docker needed) |
| Local Docker required | Yes (AZD builds locally) | No (ACR builds in the cloud) |
| AZD integration | Native, built-in | Via pre-deploy hook (still fully AZD-managed) |
| Hosting model | Container Apps (event-driven, scale to zero) | App Service (always-on, traditional scaling) |
| Scaling | Automatic, can scale to zero | Manual or autoscale rules, minimum 1 instance |
| Cost at low traffic | Potentially lower (scale to zero) | App Service Plan minimum cost applies |
| Cost at high traffic | Per-request pricing can add up | Predictable plan-based pricing |
| Maturity | Newer service, less enterprise track record | Very mature, battle-tested |
| CI/CD fit | Great for dev workflow | Great for dev workflow and GitHub Actions |
| Bicep complexity | Needs Container Apps Environment, Log Analytics link | Simpler: App Service Plan + Web App |
| Copilot agent creativity | Changed the hosting platform | Extended AZD with a hook script |

---

## When to Choose Which

Use AZD + Container Apps when:

- You want `azd up` to handle everything with zero manual steps
- You value scale-to-zero for dev/test environments
- You're comfortable with the Container Apps resource model
- You don't have (or don't want) a separate CI/CD pipeline for the deploy step

Use AZD Hook + ACR Tasks + App Service when:

- You already have App Service infrastructure (Plans, etc.)
- You don't have Docker installed locally (ACR Tasks builds in the cloud)
- You prefer the predictable pricing model of App Service Plans
- Your team is more familiar with App Service
- You want to keep the infrastructure simpler (no Container Apps Environment needed)

---

## The Mental Model

Think of AZD as a delivery app. When you say `host: containerapp`, the delivery app knows your address and brings the food. When you say `host: appservice` with Docker, the delivery app says "sorry, we don't deliver there."

Our approach: we moved to an address the delivery app supports (Container Apps).

Peer's approach: they gave the delivery app a set of custom instructions (a pre-deploy hook) that taught it how to deliver to the App Service address. The delivery app still runs the show, it just follows the extra instructions.

Both receive the same food (Docker image). Both use the same delivery app (`azd up`). The difference is whether you changed the destination or taught the driver a new route.

---

## Could We Have Made AZD Work With App Service?

Yes, and a peer proved it. The pre-deploy hook approach works and still gives you a single `azd up` experience. Our Copilot agent didn't discover this path — it jumped to switching the hosting platform instead. The peer's Copilot agent found the hook approach, which is arguably more conservative (keep App Service, extend AZD) vs. our approach which is more transformative (switch to Container Apps).

There's also a third option that avoids Docker entirely: code-based deployment with a runtime stack like DOTNET|6.0. AZD supports this natively for App Service. But then you lose Docker, which was a requirement for the workshop.

---

## Lesson for AI-Assisted Development

This was not a case of "same problem, different solutions." It was **different prompts → different issues → different constraints → different architectures**.

The peer's single sentence — "I don't want to install docker on my local machine" — cascaded through the entire pipeline:

1. **Prompt** shaped the GitHub issue's requirements
2. **Requirements** constrained the agent's solution space
3. **Constraints** forced the agent to discover AZD hooks + ACR Tasks
4. **Architecture** ended up as App Service instead of Container Apps

Our prompt didn't include that constraint, so our agent had a wider solution space and took the simpler path (Container Apps with native AZD Docker support).

The takeaway for anyone doing AI-assisted infrastructure: **the most impactful engineering decision might happen in the prompt you use to create the issue, not in the code the agent writes.** By the time the agent is coding, the architecture is already largely determined by the constraints in the issue.

This also means peer comparison is valuable — not to judge which agent is "better," but to discover which prompt constraints led to better architecture. In this case, the "no local Docker" constraint led to a more portable, cloud-native solution. That's a prompt engineering lesson, not a coding agent lesson.

---

## The AZD Conflation Problem (Peer Insight)

A peer nailed one more nuance: **our agent conflated "deploy with AZD" with "build Docker locally."**

When AZD's native Docker support requires a local Docker engine, our agent treated that as a hard coupling — if AZD handles Docker, it must build locally. So when App Service didn't support AZD's Docker flow, the agent's instinct was to switch to a host where AZD's native flow works (Container Apps) rather than decouple the build step from AZD.

The peer's agent, constrained by "no local Docker," couldn't make that same assumption. It was forced to separate concerns: let AZD orchestrate, but offload the Docker build to ACR Tasks via a hook. That decoupling is actually the more portable pattern — it works with any host type and doesn't require Docker on the developer machine.

This is a generalizable lesson about how agents resolve ambiguity: when an agent hits a limitation, it tends to change the target (path of least resistance) rather than extend the toolchain (more creative but more work). The "no local Docker" constraint removed the easy path, forcing the more creative solution.

---

## What Would Have Helped: Skills at Requirements Time

The [Azure Skills Plugin](https://devblogs.microsoft.com/all-things-azure/announcing-the-azure-skills-plugin/) (announced March 9, 2026) bundles 19+ curated Azure skills, the Azure MCP Server, and the Foundry MCP Server. Skills like `azure-prepare` encode decision trees about service selection, Docker strategies, and SKU fitting.

The irony: **we had the plugin installed and active during the entire workshop.** Every skill was available. The `azure-prepare` skill guided our Bicep generation. The Azure MCP Server provided real tools for provisioning.

But the architecture-defining moment — the `/create-issue` prompt — happened *before* any skill was consulted. The skills kicked in at coding time, not at requirements time. By then, the constraints (or lack thereof) were already baked into the issue.

If we'd asked the agent something like *"What Azure services would I need to deploy this .NET app with Docker?"* before writing the issue prompt, the `azure-prepare` skill would have surfaced:

- ACR Tasks as a cloud-build option (no local Docker needed)
- The AZD limitation with `host: appservice` + Docker
- The hook pattern as a workaround
- The Container Apps alternative with trade-offs

That consultation would have produced a more informed issue prompt, which would have produced better-constrained requirements, which would have produced a more intentional architecture.

**The lesson: skills should be in the loop at requirements time, not just implementation time.**

---

## Sharing With Workshop Attendees

This document is being shared with other L300 workshop attendees so they can learn from both paths. The key takeaways:

1. **Prompt engineering is architecture engineering.** The most impactful decision wasn't in the Bicep — it was in the sentence "I don't want to install docker on my local machine."
2. **Agents resolve ambiguity by taking the easiest path.** If you want a specific architecture, constrain the issue. If you leave it open, the agent will optimize for the smoothest deploy.
3. **Consult Azure skills before writing issue prompts.** The skills have the decision trees. Use them before the constraints are locked in.
4. **Peer comparison reveals prompt gaps, not agent gaps.** Both agents were competent. The difference was input quality.

---

## Source

- AZD Docker support limitation: https://github.com/Azure/azure-dev/issues/2646
- AZD hooks documentation: https://learn.microsoft.com/en-us/azure/developer/azure-developer-cli/azd-extensibility
- ACR Tasks documentation: https://learn.microsoft.com/en-us/azure/container-registry/container-registry-tutorial-quick-task
- App Service container deployment: https://learn.microsoft.com/en-us/azure/app-service/configure-custom-container
