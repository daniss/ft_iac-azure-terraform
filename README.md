# ft_iac — Highly Available IaaS on Azure with Terraform

Deploy a cost‑aware, highly available web stack on Azure IaaS with Terraform: multi‑AZ VMs, load balancing with session stickiness, autoscaling, secure secrets, alerts — in one command.

## Architecture (Default)
- Azure Resource Group, VNet/Subnets (public/private)
- 2+ Linux VMs (zones A/B) behind Azure Load Balancer/Application Gateway
- Session persistence enabled; shared state for app changes across instances
- Optional DB: self‑managed on VM (IaaS) or managed (à valider selon consignes)
- Autoscaling (VM Scale Set or script‑based scale policy)
- Secrets in Azure Key Vault; no secrets in repo
- Monitoring/alerts via Azure Monitor (health, HTTP 5xx, CPU/RAM)
- Bastion/Jumpbox optional for admin

Diagram: docs/diagram.png (placeholder)

## IaC Layout
```
/modules
  /network   # VNet, subnets, NSG
  /compute   # VM/VMSS, images, extensions (cloud-init)
  /lb        # LB/App Gateway, probes, rules
  /kv        # Key Vault, secrets, access policies
  /monitor   # Alerts, action groups
/environments
  /dev
    terraform.tfvars
  /prod
    terraform.tfvars
/scripts
  ha_test.sh
  scale_test.sh
  smoke.sh
```

## Region and Size Aliases
- region = "EU" | "Paris" → mapped to Azure regions (e.g., westeurope, francecentral)
- size = "small" | "medium" | "large" → mapped to VM sizes (e.g., B2s, D2s_v5, D4s_v5)

## Security
- Secrets in Key Vault only; retrieved at plan/apply via data sources
- SSH keys; inbound restricted by NSG
- No plaintext secrets, no secrets in scripts

## HA & Scalability Tests
- ha_test.sh: terminates one VM; expect no downtime from LB health probes
- scale_test.sh: synthetic load; verify scale out/in behavior and costs
- smoke.sh: session stickiness validation (login persists across refresh)

## Cost Profiles
- dev (low footprint): 1–2 small instances, minimal alerts
- prod (HA): 2+ instances across zones, full monitoring

## Usage
```
# Configure backend (remote state) and variables
cp environments/dev/terraform.tfvars.example environments/dev/terraform.tfvars
terraform -chdir=environments/dev init
terraform -chdir=environments/dev apply -auto-approve
./scripts/smoke.sh
```

## Notes (Compliance with 42 ft_iac)
- IaaS compute only (no App Service/Lambda/Functions)
- Orchestrators like Kubernetes not used
- No external Terraform modules for full stacks; custom modules only
- Zero secrets in repo

## What to Demo
- Region/size switch via single var
- Failover live test
- Scale test + cost reasoning