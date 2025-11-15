## Quick Facts

- **Cloud**: Azure (Application Gateway + VM Scale Set across zones + MySQL Flexible Server)
- **IaC**: Terraform only (no external modules)
- **Secrets**: MySQL password stored in Key Vault and fetched at runtime
- **Diagram**: `infra.png`

## Prerequisites

- Azure CLI logged in (`az login`)
- Terraform ≥ 1.0
- SSH public key at `~/.ssh/id_rsa.pub` (or set `ssh_public_key_path`)

## Deployment (5 steps)

```bash
cd azure-vm-terraform
cp terraform.tfvars.example terraform.tfvars   # fill subscription_id, db_login, alert_email
terraform init
terraform apply
terraform output public_ip_address_app_gw      # note the IP for testing
```

## Configuration knobs

| Variable | Description | Options / Notes |
| --- | --- | --- |
| `subscription_id`* | Azure subscription | required |
| `db_login`* | MySQL admin login | required |
| `alert_email`* | Email for Azure Monitor alerts | required |
| `region` | Friendly region selector | `Swiss`, `EU-West`, `EU-North`, `US-East`, `US-West` |
| `vm_size` | VMSS size profile | `small`, `medium`, `large` |
| `db_size` | MySQL SKU profile | `small`, `medium`, `large` |
| `ssh_public_key_path` | Path to SSH pubkey | default `~/.ssh/id_rsa.pub` |

## Post-deploy operations

| Goal | Command |
| --- | --- |
| Check HA (single failure) | `./test-ha.sh` |
| Stress autoscaling | `./test-scalability.sh` |
| Chaos drill (repeat failures) | `./chaos-monkey.sh 3 180` |

All scripts use Terraform outputs + Azure CLI; run them from repo root (they log to `chaos-monkey.log` / `backup-history.log`).

## Cleanup

```bash
cd azure-vm-terraform
terraform destroy
```