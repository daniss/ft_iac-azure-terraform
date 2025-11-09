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

### User-Friendly Variables (`variables.tf`)

The infrastructure supports simplified configuration using friendly names instead of technical Azure identifiers:

#### Region Selection
- **Variable**: `region`
- **Default**: `"Swiss"`
- **Options**: 
  - `"Swiss"` → switzerlandnorth
  - `"EU-West"` → westeurope
  - `"EU-North"` → northeurope
  - `"US-East"` → eastus
  - `"US-West"` → westus

#### VM Size Selection
- **Variable**: `vm_size`
- **Default**: `"small"`
- **Options**:
  - `"small"` → Standard_B2s (2 vCPU, 4 GB RAM)
  - `"medium"` → Standard_B4ms (4 vCPU, 16 GB RAM)
  - `"large"` → Standard_D4s_v3 (4 vCPU, 16 GB RAM)

#### Database Size Selection
- **Variable**: `db_size`
- **Default**: `"medium"`
- **Options**:
  - `"small"` → B_Standard_B1ms (Burstable, 1 vCore, 2 GB RAM)
  - `"medium"` → GP_Standard_D2ads_v5 (General Purpose, 2 vCore, 8 GB RAM)
  - `"large"` → GP_Standard_D4ads_v5 (General Purpose, 4 vCore, 16 GB RAM)

#### Other Required Variables
- **`subscription_id`**: Azure subscription ID (**REQUIRED** - no default)
- **`alert_email`**: Email address for monitoring alerts (**REQUIRED** - no default)

#### Other Optional Variables
- **`prefix`**: Resource name prefix (default: `"win-vm-iis"`)
- **`ssh_public_key_path`**: Path to SSH public key (default: `"~/.ssh/id_rsa.pub"`)

### Example Configurations

**Using terraform.tfvars file (recommended):**
```bash
# Copy the example file
cp terraform.tfvars.example terraform.tfvars

# Edit terraform.tfvars with your values
# subscription_id = "your-subscription-id"
# alert_email = "your-email@example.com"

terraform apply
```

**Minimal cost development setup:**
```bash
terraform apply \
  -var="subscription_id=YOUR_SUBSCRIPTION_ID" \
  -var="alert_email=your-email@example.com" \
  -var="region=Swiss" \
  -var="vm_size=small" \
  -var="db_size=small"
```

**Production setup in EU:**
```bash
terraform apply \
  -var="subscription_id=YOUR_SUBSCRIPTION_ID" \
  -var="alert_email=admin@company.com" \
  -var="region=EU-West" \
  -var="vm_size=medium" \
  -var="db_size=large"
```

**High-performance US deployment:**
```bash
terraform apply \
  -var="subscription_id=YOUR_SUBSCRIPTION_ID" \
  -var="alert_email=admin@company.com" \
  -var="region=US-East" \
  -var="vm_size=large" \
  -var="db_size=large"
```

### Infrastructure Constants
These values are fixed in the Terraform configuration:
- **VMSS instances**: Minimum 2, maximum 5 (default 2)
- **Availability zones**: [1, 2]
- **VNet CIDR**: 10.0.0.0/16
- **App Gateway capacity**: 2
- **MySQL HA mode**: ZoneRedundant
- **Admin username**: `azureuser`

## Session Persistence Strategy

**Cookie-based affinity** via Application Gateway:
- Client receives `AppGwAffinityCookie` on first request
- Subsequent requests from same client routed to same VMSS instance
- Sessions survive page refreshes, browser navigation
- If backend instance fails, health probe removes it and new session established

## Security Implementation

### Secrets Management
- **No secrets in code**: All sensitive values must be provided via terraform.tfvars or command-line variables
- **Subscription ID**: Must be provided by user (no default value in code)
- **Database password**: Generated automatically via `random_password` resource
- **Key Vault storage**: Secrets stored as `dbPassword` in Azure Key Vault
- **RBAC authorization**: Key Vault uses role-based access control
  - Terraform/admin: `Key Vault Administrator` role
  - VMSS instances: `Key Vault Secrets User` role (read-only)
- **Managed Identity**: VMSS has system-assigned identity for passwordless Key Vault access
- **Soft delete**: 7-day retention for deleted secrets
- **Git ignored**: terraform.tfvars and state files are excluded from version control

### Network Security
- **NSG Rules**:
  - App Subnet: Allow HTTP (80) from App Gateway subnet (10.0.0.0/24)
  - DB Subnet: Allow MySQL (3306) from App Subnet (10.0.1.0/24)
- **Private Database**: MySQL accessible only via private endpoint in VNet
- **SSH Access**: Public key authentication only (configurable path via `ssh_public_key_path` variable)

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
3. **SSH Key**: Public key (default location: `~/.ssh/id_rsa.pub`, or specify custom path)
4. **Azure Subscription**: ID required for deployment (get with `az account show --query id -o tsv`)
5. **Configuration File**: Copy `terraform.tfvars.example` to `terraform.tfvars` and fill in your values

### Deploy Infrastructure

```bash
cd azure-vm-terraform

# Configure your variables
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars and set:
# - subscription_id (REQUIRED)
# - alert_email (REQUIRED)
# - Other optional variables as needed

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

## Testing

### High Availability Test
```bash
./test-ha.sh
```
Tests server failure recovery by deleting a VMSS instance and monitoring automatic recovery.

### Autoscaling Test
```bash
./test-scalability.sh
```
Generates load to trigger CPU-based autoscaling (requires apache2-utils for `ab` command).

## Known Limitations & Future Enhancements

### Limitations
- **Bastion Access**: No direct SSH access to VMSS instances (private subnet only). Use Azure Bastion or temporary NSG rules for troubleshooting.
- **Remote State**: No backend configuration for shared Terraform state (uses local state file)
- **Environment Separation**: No dev/prod environment structure

### Potential Enhancements
- Multi-region deployment with global load balancing
- HTTPS/TLS with custom domain and Azure Front Door
- Log Analytics workspace for centralized logging
- Application Insights for APM monitoring
- Azure DevOps pipeline for CI/CD
- Chaos engineering tests for resilience validation
- **CI/CD**: No automated testing or deployment pipeline