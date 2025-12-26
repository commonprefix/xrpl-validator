# XRPL Validator Infrastructure

Moderately opinionated Terraform and Ansible configuration for running XRPL validator clusters on AWS.

## Background

### Validators vs Nodes

**Nodes** are rippled servers that:
- Sync with the network and maintain a copy of the ledger
- Accept and relay transactions
- Serve API requests
- Do NOT participate in consensus

**Validators** are rippled servers that:
- Do everything stock nodes do, PLUS
- Participate in consensus by proposing and voting on transaction sets
- Must be highly available and secure (network disruption affects consensus)

### Cluster

Running a validator directly exposed to the internet is risky:
- DDoS attacks can take it offline, harming network consensus
- IP address exposure makes it a target
- Direct peer connections increase attack surface

The solution is a **cluster**: one hidden validator behind multiple proxy nodes.

```mermaid
flowchart TD
    Internet((Internet))

    subgraph public["Public Subnet"]
        PublicNode[Public Node<br/>proxy]
    end

    subgraph private["Private Subnet"]
        PrivateNode[Private Node<br/>proxy]
    end

    subgraph isolated["Isolated Private Subnet"]
        Validator[Validator<br/>proposing]
    end

    Internet <--> PublicNode
    Internet --> PrivateNode

    PublicNode --> Validator
    PrivateNode --> Validator
```

- **Validator**: Hidden in an isolated subnet with its own NAT gateway (prevents IP leakage of any sorts). Only accepts connections from trusted proxy nodes. Runs in "proposing" state.
- **Public nodes**: Have public IPs, accept inbound peer connections from the internet. Act as proxies.
- **Private nodes**: No public IP, outbound-only connections via NAT. Still proxy for the validator but don't accept random inbound peers.

All nodes in the cluster share public keys and communicate as trusted peers.

For more background, see the [Rabbitkick XRPL Validator Guide](https://rabbitkick.club/rippled_guide/rippled.html).

## Project Structure

### Environments

Each environment (e.g., `testnet`, `mainnet`) is a completely isolated cluster with its own:
- VPC and networking
- EC2 instances
- Secrets in AWS Secrets Manager
- CloudWatch alarms and dashboard
- S3 buckets for wallet.db backup

Environments are defined in `terraform/<environment>/main.tf`. See `terraform/testnet/` as a reference.

### Terraform Module

The core infrastructure is defined in a reusable module at `terraform/modules/validator-cluster/`. Each environment imports this module and configures it.

### Ansible

Ansible configures the instances after Terraform provisions them. It uses a dynamic inventory (`ansible/inventory/aws_ec2.yml`) that discovers instances by EC2 tags. Instances are grouped by:
- `env_<environment>` - all instances in an environment (e.g., `env_testnet`)
- `name_<name>` - individual instances (e.g., `name_testnet_validator`)
- `role_validator` / `role_node` - by role

## Prerequisites

- AWS CLI configured with credentials
- Terraform >= 1.0
- Ansible >= 2.10 (install from your package manager; `community.aws` and `amazon.aws` collections typically included)
- Session Manager plugin for AWS CLI

### IAM Role for Terraform

Terraform needs an IAM role with permissions for EC2, VPC, IAM, CloudWatch, SNS, SSM, and S3. The role should cover:

- **EC2**: Full VPC management (subnets, NAT gateways, security groups, instances)
- **IAM**: Create/manage roles and instance profiles (scoped to `*-validator`, `*-node-*`, `*-ansible` patterns)
- **CloudWatch**: Alarms, dashboards, log groups
- **SNS**: Alert topics
- **SSM**: Patch baselines, maintenance windows
- **S3**: State bucket access, Ansible SSM bucket, wallet.db backup bucket

Whichever principal is running Terraform needs to be able to assume the role. 

## Usage

To deploy or update an environment:

### 1. Deploy Infrastructure

```bash
export AWS_PROFILE=your-profile
cd terraform/myenv
terraform init
terraform plan
terraform apply
```

### 2. Configure Instances with Ansible

```bash
cd ansible
export AWS_PROFILE=your-profile
ansible-playbook playbooks/site.yml -l env_myenv
```

### Node Configuration Reference

Each node in the `nodes` list accepts:

| Field | Required | Description |
|-------|----------|-------------|
| `name` | Yes | Unique name for the node (used in AWS tags, alarms, etc.) |
| `instance_type` | Yes | EC2 instance type. It's best to use an instance family with NVMe instance storage. |
| `root_volume_size` | Yes | Root EBS volume size in GB. This needs to be sufficient for logs, configuration, binaries, etc. |
| `availability_zone` | Yes | Index into `availability_zones` list (0, 1, etc.) |
| `validator` | No | Set to `true` for the validator. Exactly one node must have this. Default: `false` |
| `public` | No | Set to `true` for public subnet with public IP. Validators cannot be public. Default: `false` |
| `secret_name` | Yes | AWS Secrets Manager path for sensitive data (validation_seed, validator_token). |
| `var_secret_name` | Yes | AWS Secrets Manager path for public data (validation_public_key) |
| `ssl_subject` | No | SSL certificate details for peer connections. Required for non-validator nodes |
| `ledger_history` | No | Number of ledgers to retain. Default: `6000` |
| `node_size` | No | rippled node size (tiny, small, medium, large, huge). Default: `medium` |

### Module-Level Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `environment` | Environment name (used in resource names, tags) | Required |
| `region` | AWS region | Required |
| `availability_zones` | List of AZs to use | Required |
| `vpc_cidr` | VPC CIDR block | `10.0.0.0/16` |
| `patch_schedule` | Cron for OS patching (UTC) | `cron(0 11 ? * MON *)` (Mondays 11:00 UTC) |
| `log_retention_days` | CloudWatch log retention | `30` |
| `rippled_log_max_size_mb` | Max rippled log size before rotation | `1024` |
| `rippled_log_max_files` | Rotated log files to keep | `10` |
| `ansible_role_principals` | IAM ARNs that can assume Ansible role | `[]` |
| `alarm_thresholds` | Alarm threshold configuration (see below) | See defaults |

Alarm thresholds:
```hcl
alarm_thresholds = {
  ledger_age_seconds  = 20   # Alert if ledger age exceeds this
  node_min_peer_count = 5    # Alert if node has fewer peers
  disk_used_percent   = 75   # Alert if disk usage exceeds this
  memory_used_percent = 75   # Alert if memory usage exceeds this
  cpu_used_percent    = 75   # Alert if CPU usage exceeds this
}
```

## How Ansible Works

Ansible runs after Terraform provisions the instances. It performs these steps:

### NVMe Storage Setup

Instances use NVMe instance storage for `/var/lib/rippled`. This storage is **ephemeral** - it's wiped when the instance stops (but preserved on reboot). A systemd service automatically reformats it on boot if needed.

### Secret Management

Each node requires two secrets in AWS Secrets Manager. You can either:
- **Pre-create them** before running Ansible (e.g., when migrating an existing validator)
- **Let Ansible create them** automatically on first run

If the secrets don't exist or are empty, Ansible runs `rippled validation_create` to generate new keys and populates both secrets.

#### Secret Structure

**`secret_name`** - Sensitive data (only accessible by the node's EC2 instance):

For nodes (SSL cert/key are auto-generated and added on first run):
```json
{
  "validation_seed": "ssXXXXXXXXXXXXXXXXXXXXXXXXXXX",
  "ssl_key": "-----BEGIN PRIVATE KEY-----\n...",
  "ssl_cert": "-----BEGIN CERTIFICATE-----\n..."
}
```

For validators (no SSL - validator doesn't expose peer port):
```json
{
  "validation_seed": "ssXXXXXXXXXXXXXXXXXXXXXXXXXXX",
  "validator_token": "XXXXXXXXXXXXXXXXXXXXXXXXXXX..."
}
```

The SSL certificate is self-signed with a 10-year validity, using the `ssl_subject` configuration from Terraform (CN, O, C fields). Once generated, it's stored in the secret and restored on subsequent runs.

**`var_secret_name`** - Public data (readable by all nodes for cluster config):
```json
{
  "validation_public_key": "n9XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX"
}
```

#### Pre-creating Secrets (Migration Use Case)

If you're migrating an existing validator or want to use specific keys:

```bash
# Create the secret with your existing keys
aws secretsmanager create-secret --region ap-south-1 \
  --name "rippled/myenv/secret/validator" \
  --secret-string '{
    "validation_seed": "ssYourExistingSeed...",
    "validator_token": "eyYourExistingToken..."
  }'

aws secretsmanager create-secret --region ap-south-1 \
  --name "rippled/myenv/var/validator" \
  --secret-string '{
    "validation_public_key": "n9YourExistingPublicKey..."
  }'
```

When Ansible runs, it will detect these existing secrets and use them instead of generating new ones.


### wallet.db Persistence

rippled stores node identity in `wallet.db`. Since NVMe storage is ephemeral, systemd services handle backup/restore:

- **On boot**: Restores wallet.db from S3 before rippled starts
- **Hourly**: Backs up wallet.db to S3
- **On stop**: Backs up wallet.db before shutdown

Each node can only access its own S3 path (IAM-enforced).

### Cluster Configuration

Ansible fetches public keys from all other nodes' `var_secret_name` and builds the cluster configuration. All nodes trust each other as peers.

## Operations

### Accessing Instances

No SSH. Use AWS Systems Manager Session Manager:

```bash
aws ssm start-session --region <region> --target <instance-id>
```

### Adding a Node

1. Add to `nodes` list in Terraform
2. `terraform apply`
3. Configure new node: `ansible-playbook playbooks/site.yml -l name_myenv_node_X`
4. Update cluster config on all nodes: `ansible-playbook playbooks/site.yml -l env_myenv`

### Upgrading rippled

```bash
# Connect to instance
aws ssm start-session --region <region> --target <instance-id>

# Run upgrade
sudo /usr/local/bin/update-rippled-aws

# Verify
rippled server_info | grep build_version
```

For rolling upgrades: upgrade nodes first (wait for `full` state), then validator last.

### Useful Commands

```bash
# Run on all instances in environment
ansible-playbook playbooks/site.yml -l env_myenv

# Run on specific instance
ansible-playbook playbooks/site.yml -l name_myenv_node_1

# Restart rippled everywhere
ansible env_myenv -m systemd -a "name=rippled state=restarted" --become

# Check server state
ansible env_myenv -m shell -a "rippled server_info | jq .result.info.server_state" --become

# List available hosts
ansible-inventory -i inventory/aws_ec2.yml --graph
```

### Monitoring

The module creates:
- **CloudWatch Dashboard**: `rippled-<environment>` with server state, peers, ledger metrics, system metrics
- **CloudWatch Alarms**: Server state, ledger age, peer count, cluster connectivity, disk/memory/CPU, reboot required
- **SNS Topics**: `<environment>-rippled-alerts` for notifications

Subscribe to the SNS topic for alerts (email, PagerDuty, Discord, etc.).

The dashboard is created for every environment. Since it is managed by Terraform, please resist the urge to change it directly in AWS console.

![dashboard](docs/dashboard.png)


### Validator Token

When Ansible first runs on a new validator, it generates a `validation_seed` which gives the node a **peer identity** for cluster communication. However, to actually **participate in consensus** (propose and vote on transactions), you need a `validator_token`.

Generate a validator token on a secure machine:

```bash
# Generate the master key (store this securely offline!)
/opt/ripple/bin/validator-keys create_keys
# Output: validator-keys.json in ~/.ripple/

# Optionally set your domain for identification
/opt/ripple/bin/validator-keys set_domain yourdomain.com

# Generate a token from the master key
/opt/ripple/bin/validator-keys create_token
```

Then add the token to your validator's secret:

```bash
aws secretsmanager update-secret --region <region> \
  --secret-id "rippled/myenv/secret/validator" \
  --secret-string '{
    "validation_seed": "ssExistingSeed...",
    "validator_token": "validation_secret_key..."
  }'
```

Re-run Ansible on the validator to apply:

```bash
ansible-playbook playbooks/site.yml -l name_myenv_validator
```

The validator will now participate in consensus. You can verify with:

```bash
rippled server_info | grep server_state
```
