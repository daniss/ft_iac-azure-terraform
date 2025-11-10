## Prerequisites

- Azure CLI installed and logged in (`az login`)
- SSH key at `~/.ssh/id_rsa.pub`

## Deploy

```bash
cd azure-vm-terraform

terraform init

terraform apply

terraform output public_ip_address_app_gw
```

## Configuration

**Required variables** (must be provided):
- **subscription_id**: Your Azure subscription ID
- **db_login**: MySQL administrator username
- **alert_email**: Email for monitoring alerts


**Available options:**
- **region**: `Swiss`, `EU-West`, `EU-North`, `US-East`, `US-West`
- **vm_size**: `small`, `medium`, `large`
- **db_size**: `small`, `medium`, `large`

## Test High Availability

```bash
./test-ha.sh

```

## Clean Up

```bash
cd azure-vm-terraform
terraform destroy
```
See `infra.png` for architecture diagram.