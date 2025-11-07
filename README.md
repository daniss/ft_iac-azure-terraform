# ft_iac — Highly Available IaaS on Azure with Terraform

Deploy a highly available web application on Azure using Terraform: Application Gateway with cookie-based session affinity, autoscaling VMSS across availability zones, MySQL Flexible Server with zone redundancy, and secure secret management with Key Vault.

## Architecture (Implemented)

### Network Layer
- **VNet**: 10.0.0.0/16 address space
  - **App Gateway Subnet** (10.0.0.0/24): Hosts Application Gateway v2
  - **App Subnet** (10.0.1.0/24): Hosts VMSS instances across zones 1 & 2
  - **DB Subnet** (10.0.2.0/24): Private subnet for MySQL Flexible Server with service delegation
- **NSGs**: Security rules allow HTTP traffic from App Gateway to VMs, MySQL traffic from App Subnet to DB Subnet
- **Private DNS Zone**: `privatelink.mysql.database.azure.com` for private database connectivity

### Compute Layer
- **VMSS**: Linux (Ubuntu 20.04 LTS) virtual machine scale set
  - **Zones**: Deployed across availability zones 1 & 2
  - **Instances**: Minimum 2, maximum 5 (default 2)
  - **Size**: Configurable via `app_vm_size` variable (default: Standard_B2s)
  - **Autoscaling**: CPU-based rules (scale out >75%, scale in <25%)
  - **Identity**: System-assigned managed identity with Key Vault Secrets User role
  - **SSH**: Public key authentication (requires ~/.ssh/id_rsa.pub)

### Load Balancing
- **Application Gateway v2** (Standard_v2)
  - **Cookie-based session affinity**: Enabled with `AppGwAffinityCookie`
  - **Health probe**: HTTP on port 80, path "/", 30s interval
  - **Zones**: Deployed across zones 1 & 2
  - **Public IP**: Static Standard SKU across zones 1, 2, 3
  - **Backend pool**: Automatically populated with VMSS instances

### Database
- **MySQL Flexible Server 8.0.21**
  - **SKU**: GP_Standard_D2ads_v5
  - **High Availability**: Zone-redundant mode
  - **Backup**: 7-day retention
  - **Network**: Private access via delegated subnet
  - **Credentials**: Stored securely in Key Vault

### Secrets Management
- **Azure Key Vault**
  - **Authorization**: RBAC-enabled (Key Vault Administrator for Terraform, Secrets User for VMSS)
  - **Soft delete**: 7-day retention
  - **Secrets**: Database password stored as `dbPassword`
  - **Access**: VMSS managed identity has read-only access

### Storage
- **Diagnostics Storage**: LRS storage account for VM boot diagnostics

## Project Structure

```
azure-vm-terraform/
├── main.tf              # Resource group, random generators
├── providers.tf         # Terraform & Azure provider config
├── variables.tf         # Input variables (region, size, prefix)
├── outputs.tf           # Resource group name, App Gateway public IP
├── network.tf           # VNet, subnets, NSGs, public IPs, DNS zones
├── vmss.tf              # VMSS, autoscaling, RBAC role assignments
├── appgateway.tf        # Application Gateway v2 configuration
├── database.tf          # MySQL Flexible Server
├── keyvault.tf          # Key Vault, secrets, RBAC roles
└── storage.tf           # Storage account for diagnostics
```

## Configuration Variables

### Implemented Variables (`variables.tf`)
- **resource_group_location**: Default `"switzerlandnorth"`
- **prefix**: Default `"win-vm-iis"` (used in resource naming with random pet suffix)
- **app_vm_size**: Default `"Standard_B2s"` (VM size for VMSS instances)

### Hardcoded Values
- **VMSS instances**: 2 (minimum), 5 (maximum)
- **Availability zones**: [1, 2]
- **VNet CIDR**: 10.0.0.0/16
- **App Gateway capacity**: 2
- **MySQL HA mode**: ZoneRedundant
- **Admin username**: `azureuser`
- **Subscription ID**: Hardcoded in providers.tf

## Session Persistence Strategy

**Cookie-based affinity** via Application Gateway:
- Client receives `AppGwAffinityCookie` on first request
- Subsequent requests from same client routed to same VMSS instance
- Sessions survive page refreshes, browser navigation
- If backend instance fails, health probe removes it and new session established

## Security Implementation

### Secrets Management
- **No secrets in code**: Database password generated via `random_password` resource
- **Key Vault storage**: Secrets stored as `dbPassword` in Azure Key Vault
- **RBAC authorization**: Key Vault uses role-based access control
  - Terraform/admin: `Key Vault Administrator` role
  - VMSS instances: `Key Vault Secrets User` role (read-only)
- **Managed Identity**: VMSS has system-assigned identity for passwordless Key Vault access
- **Soft delete**: 7-day retention for deleted secrets

### Network Security
- **NSG Rules**:
  - App Subnet: Allow HTTP (80) from App Gateway subnet (10.0.0.0/24)
  - DB Subnet: Allow MySQL (3306) from App Subnet (10.0.1.0/24)
- **Private Database**: MySQL accessible only via private endpoint in VNet
- **SSH Access**: Public key authentication only (requires ~/.ssh/id_rsa.pub file)

### High Availability Features
- **Multi-zone deployment**: VMSS and App Gateway across zones 1 & 2
- **Zone-redundant MySQL**: Automatic failover between availability zones
- **Health probes**: App Gateway monitors backend health every 30s
- **Autoscaling**: Automatic scale out/in based on CPU metrics
- **Backup retention**: 7-day MySQL backups

## Autoscaling Configuration

**CPU-based scaling rules**:
- **Scale out**: When CPU > 75% for 5 minutes → add 1 instance (cooldown: 5 min)
- **Scale in**: When CPU < 25% for 5 minutes → remove 1 instance (cooldown: 5 min)
- **Capacity**: Minimum 2, maximum 5, default 2 instances
- **Metric**: Percentage CPU average over 1-minute intervals

## Deployment

### Prerequisites
1. **Azure CLI**: Authenticated with `az login`
2. **Terraform**: Version >=1.0
3. **SSH Key**: Public key at `~/.ssh/id_rsa.pub`
4. **Azure Subscription**: ID configured in `providers.tf`

### Deploy Infrastructure

```bash
cd azure-vm-terraform

# Initialize Terraform
terraform init

# Preview changes
terraform plan

# Deploy infrastructure
terraform apply

# Get Application Gateway public IP
terraform output public_ip_address_app_gw
```

### Access Application
```bash
# Get the public IP from outputs
APP_IP=$(terraform output -raw public_ip_address_app_gw)

# Test HTTP endpoint
curl http://$APP_IP

# Verify session persistence (cookie should be set)
curl -v http://$APP_IP
```

### SSH to VMSS Instances
VMSS instances are in a private subnet behind App Gateway. To access them:

1. **Option A**: Deploy a bastion host (not yet implemented)
2. **Option B**: Use Azure Bastion service
3. **Option C**: Add temporary NSG rule + public IP for development

### Clean Up
```bash
terraform destroy
```

## Known Limitations & TODOs

### Not Yet Implemented
- **Bastion/Jumpbox**: No SSH access to VMSS instances (private subnet only)
- **Application deployment**: No cloud-init script to deploy NestJS application
- **Monitoring & Alerts**: No Azure Monitor alerts for health/CPU/HTTP errors
- **Region aliases**: No mapping for simplified region names (EU/Paris/US)
- **Size aliases**: No mapping for small/medium/large VM sizes
- **Remote state**: No backend configuration for shared Terraform state
- **Environment separation**: No dev/prod environment structure
- **CI/CD**: No automated testing or deployment pipeline