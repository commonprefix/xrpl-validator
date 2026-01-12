# XRPL Validator Infrastructure

Moderately opinionated Terraform and Ansible configuration for running XRPL validator clusters on AWS.

## Cluster Setup

This setup runs two types of rippled servers: 

**Nodes** sync with the network, keep a copy of the ledger, and relay transactions. Nodes work in a cluster alongside a validator, acting as a sort of proxy between the network and the validator. They don't participate in consensus though.

**Validator** runs in a cluster with nodes and participates in consensus. 

The validator hides behind a **cluster** of proxy nodes. The validator sits in an isolated subnet with no direct internet access. The proxy nodes handle all the public-facing traffic and relay messages to the validator.

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

Each environment (e.g., `testnet`, `mainnet`) is a completely isolated cluster with its own VPC, EC2 instances, secrets, and monitoring. Environments are defined in `terraform/<environment>/main.tf`. See `terraform/testnet/` as a reference.

#### VPC and Networking

The module creates a VPC with three tiers of subnets:

- **Public subnets** for nodes that need to accept inbound connections from the internet. These get public IPs and use an internet gateway.
- **Private subnets** for nodes that only make outbound connections. Traffic goes through a shared NAT gateway.
- **Validator subnet** is completely isolated private subnet with a dedicated NAT gateway.

#### EC2 Instances

To keep things simple, we decided to deploy rippled to a set of provisioned EC2 instances. The reasons why we don't containerize rippled and run containers in something like ECS or K8S:
- The number of validators will not scale and we will never want to run two validators with the same configuration. In fact, this setup only assumes one validator will ever run in a cluster.
- While it could make sense for nodes to scale, we do not anticipate a demand for scaling based on objective metrics. 
- Each node is likely to be very unique in its setup. For example, if a node is also used by an application to fetch historical data, that setup will be quite different to a node that is used for redundancy in a cluster. 
- All nodes and validators require SSD storage. We can't trivially location-balance them without making sure we stop them, copy all history and then start on new machine. While this can of course be achieved with a container orchestration tool, we don't anticipate the need right now.

It is quite likely that we will eventually want to have two nodes with long history used for redundancy (so one can be updated while the other one) used by a external application, in which case, for now, we will keep them behind a load balancer. 

Instances are configured in the `nodes` list. Each one gets an IAM role scoped to just its own secrets and S3 paths. The module uses instance types with NVMe storage (like z1d) - the local NVMe drive is mounted at `/var/lib/rippled` for ledger data. This storage is ephemeral (wiped on stop, preserved on reboot), which is fine since rippled can resync from the network.

All instances have termination and stop protection enabled to prevent accidents. They're also set up for Systems Manager access instead of SSH.

EC2 instances are provisioned by Terraform and managed by Ansible.

#### Secrets

Each node has two secrets in AWS Secrets Manager. The "secret" one holds sensitive data like the validation seed and SSL keys - only that specific instance can read it. The "var" one holds public data like the validation public key, which all nodes can read so they can build their cluster configuration.

IAM policies ensure nodes can only access their own secrets and other nodes' public data.

#### CloudWatch

The module sets up alarms for both rippled health and system health. 

There's also an instance status check alarm that automatically reboots the instance if the OS becomes unresponsive. All alarms notify an SNS topic you can subscribe to.

Also, each cluster gets its dashboard.

### Ansible

Ansible configures the instances after Terraform provisions them. It uses a dynamic inventory (`ansible/inventory/aws_ec2.yml`) that discovers instances by EC2 tags. Instances are grouped by:
- `env_<environment>` - all instances in an environment (e.g., `env_testnet`)
- `name_<name>` - individual instances (e.g., `name_testnet_validator`)
- `role_validator` / `role_node` - by role


# Usage

## Prerequisites

- AWS CLI configured with credentials
- Terraform >= 1.0
- Ansible >= 2.10 (install from your package manager; `community.aws` and `amazon.aws` collections typically included)
- Session Manager plugin for AWS CLI

### IAM Role for Terraform

User or process running Terraform needs an IAM role with permissions for EC2, VPC, IAM, CloudWatch, SNS, SSM, and S3. The role should cover:

- **EC2**: Full VPC management (subnets, NAT gateways, security groups, instances)
- **IAM**: Create/manage roles and instance profiles (scoped to `*-validator`, `*-node-*`, `*-ansible` patterns)
- **CloudWatch**: Alarms, dashboards, log groups
- **SNS**: Alert topics
- **SSM**: Patch baselines, maintenance windows
- **S3**: State bucket access, Ansible SSM bucket, wallet.db backup bucket

## Steps

### 1. Deploy Infrastructure

```bash
export AWS_PROFILE=your-profile
cd terraform/<env>
terraform init
terraform plan
terraform apply
```

### 2. Configure Instances with Ansible

```bash
cd ansible
export AWS_PROFILE=your-profile
ansible-playbook playbooks/site.yml -l env_<env>
```

## Node Configuration Reference

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

# Cheat-Sheet

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
