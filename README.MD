# Clawdbot AWS — EC2 Deployment

Deploy [OpenClaw](https://github.com/openclaw/openclaw) (AI assistant) on a `t3.medium` EC2 instance with automated provisioning via Terraform and GitHub Actions.

## Architecture

```mermaid
flowchart TB
    subgraph GH["GitHub Actions"]
        PR["Push to main"]
        WF["Terraform Workflow<br/>(ubuntu-latest)"]
        PR --> WF
    end

    subgraph AUTH["Authentication"]
        OIDC["GitHub OIDC Provider<br/>(token.actions.githubusercontent.com)"]
        STS["AWS STS<br/>AssumeRoleWithWebIdentity"]
        ROLE["IAM Role<br/>clawdbot-github-actions"]
    end

    subgraph AWS["AWS Account"]
        subgraph VPC["Default VPC"]
            SG["Security Group<br/>SSH restricted + HTTPS/DNS egress"]
            subgraph EC2["EC2 Instance (t3.medium)"]
                OS["Debian 12 Bookworm"]
                NODE["Node.js 22 (nvm)"]
                OC["OpenClaw Gateway"]
                PROF["Instance Profile<br/>clawdbot-ec2-profile"]
            end
        end
        EBS["EBS gp3 30GB<br/>(encrypted)"]
        CW["CloudWatch Logs"]
        SSM["SSM Session Manager"]
    end

    subgraph R2["Cloudflare R2"]
        STATE["Terraform State<br/>(S3-compatible backend)"]
    end

    subgraph EXT["External Services"]
        ANTH["Anthropic API"]
        DISC["Discord Gateway"]
        SIG["Signal Protocol"]
        GITAPI["GitHub/Gitea API"]
    end

    WF -- "1. Request OIDC token" --> OIDC
    OIDC -- "2. Verify & issue" --> STS
    STS -- "3. Temporary credentials" --> ROLE
    ROLE -- "4. Terraform plan/apply" --> EC2
    WF -- "Read/write state" --> STATE
    EC2 --- EBS
    EC2 -- "HTTPS (443)" --> EXT
    PROF -- "Logs" --> CW
    PROF -- "Remote access" --> SSM
    SG -. "Ingress: SSH only<br/>(restricted CIDRs)" .-> EC2
    SG -. "Egress: 443, 80, 53" .-> EXT

    style GH fill:#24292e,color:#fff
    style AWS fill:#232f3e,color:#fff
    style R2 fill:#f38020,color:#fff
    style AUTH fill:#4a90d9,color:#fff
    style EXT fill:#2d5016,color:#fff
```

## Deployment Flow

```mermaid
sequenceDiagram
    participant Dev as Developer
    participant GH as GitHub Actions
    participant OIDC as GitHub OIDC
    participant STS as AWS STS
    participant TF as Terraform
    participant R2 as Cloudflare R2
    participant AWS as AWS

    Dev->>GH: Push to main (*.tf)
    GH->>OIDC: Request OIDC token
    OIDC->>STS: Federated auth (JWT)
    STS-->>GH: Temporary credentials
    GH->>R2: terraform init (load state)
    R2-->>GH: Current state
    GH->>TF: terraform plan
    TF->>AWS: API calls (plan)
    AWS-->>TF: Resource state
    TF-->>GH: Plan output
    GH->>TF: terraform apply
    TF->>AWS: Create/update resources
    AWS-->>TF: Resource IDs
    TF->>R2: Write updated state
    Note over AWS: EC2 boots with userdata<br/>Installs Node.js + OpenClaw
```

## What's Deployed

| Resource | Details |
|----------|---------|
| **EC2 Instance** | t3.medium (2 vCPU, 4 GB RAM) — Debian 12 |
| **EBS Volume** | 30 GB gp3, encrypted, delete-on-termination |
| **Security Group** | SSH ingress (restricted CIDRs), HTTPS/HTTP/DNS egress |
| **Key Pair** | SSH public key for instance access |
| **User Data** | Automated bootstrap: Node.js, OpenClaw, systemd service |
| **IAM OIDC Provider** | GitHub Actions federated auth (no static keys) |
| **IAM Role** | `clawdbot-github-actions` — least-privilege Terraform role |
| **Instance Profile** | `clawdbot-ec2-profile` — CloudWatch Logs + SSM access |

### Security Highlights
- **OIDC federation** — no static AWS credentials in GitHub Secrets
- **IMDSv2 enforced** (no v1 token requests)
- **SSH restricted** to explicitly allowed CIDRs (default: none)
- **Egress limited** to HTTPS (443), HTTP (80), and DNS (53)
- **EBS encrypted** at rest
- **Least-privilege IAM** — scoped to clawdbot resources only
- **Instance profile** — EC2 uses IAM role, not baked-in credentials

## Prerequisites

- AWS account with default VPC
- [Cloudflare R2 bucket](https://developers.cloudflare.com/r2/) for Terraform state backend
- GitHub repository with Actions enabled

### Cloudflare R2 Setup (State Backend)

1. Go to **Cloudflare Dashboard → Storage & Databases → R2 → Create Bucket**
2. Choose **wnam** location, **Standard** storage class
3. Create an **R2 API Token** with **Object Read & Write** permissions
4. Note the **bucket name**, **endpoint URL**, **access key**, and **secret key**

> R2 free tier covers this easily — tfstate files are tiny.

### IAM Setup

The `iam.tf` file creates a GitHub Actions OIDC provider and deployment role automatically. For the **initial bootstrap** (first `terraform apply`), you need an IAM user with admin-level permissions to create the OIDC provider and roles. After that, the GitHub Actions workflow uses OIDC federation — no static keys needed.

<details>
<summary>Bootstrap IAM Policy (first apply only)</summary>

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "EC2Deploy",
      "Effect": "Allow",
      "Action": [
        "ec2:*",
        "iam:*"
      ],
      "Resource": "*"
    }
  ]
}
```

> ⚠️ Scope this down or delete the bootstrap user after the OIDC provider is created.

</details>

## GitHub Actions Setup

### Repository Secrets

Go to **Settings → Secrets and variables → Actions** and add:

| Secret | Description |
|--------|-------------|
| `AWS_ROLE_ARN` | ARN of `clawdbot-github-actions` role (after bootstrap) |
| `BUCKET_NAME` | R2 bucket name |
| `BUCKET_KEY` | State file path (e.g. `clawdbot-aws/terraform.tfstate`) |
| `BUCKET_ENDPOINT` | `https://<account-id>.r2.cloudflarestorage.com` |
| `BUCKET_ACCESS_KEY_ID` | R2 API access key |
| `BUCKET_SECRET_ACCESS_KEY` | R2 API secret key |
| `SSH_PUBLIC_KEY` | Your SSH public key (full key string) |
| `ALLOWED_SSH_CIDRS` | JSON array of CIDRs, e.g. `["1.2.3.4/32"]` |

> **Note:** After OIDC is set up, `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` are no longer needed.

### Workflows

| Workflow | Trigger | What it does |
|----------|---------|-------------|
| **terraform-build** | Push to `main` (*.tf, userdata.sh) | Plan + Apply |
| **terraform-destroy** | Manual dispatch | Destroy all resources |

> **Note:** Enable **Read and write permissions** under Settings → Actions → General → Workflow permissions.

## Post-Deploy Setup

After the instance is running:

```bash
# SSH in (Debian default user is 'admin')
ssh -i ~/.ssh/your-key admin@<public-ip>

# Switch to clawdbot user
sudo su - clawdbot

# Configure OpenClaw
openclaw init

# Start the service
sudo systemctl start openclaw
```

The bootstrap script (userdata.sh) automatically installs Node.js, OpenClaw, and creates a systemd service.

## Customization

| Variable | Default | Description |
|----------|---------|-------------|
| `aws_region` | `us-west-2` | AWS region |
| `instance_type` | `t3.medium` | EC2 instance type |
| `root_volume_size` | `30` | EBS volume size (GB) |
| `node_version` | `22` | Node.js major version |
| `subnet_id` | `""` | Subnet (empty = default VPC) |
| `allowed_ssh_cidrs` | `[]` | SSH access CIDRs |
| `github_repo` | `drewpypro/clawdbot-aws` | Repo for OIDC federation |
| `state_bucket` | `""` | R2/S3 bucket for TF state |

## Optional: Cloudflare DNS

The `dns.tf` file contains commented-out examples for CNAME records via Cloudflare. Uncomment and configure if you want DNS pointing to your instance.

Requires additional secrets: `CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ZONE_ID`.

## Costs

**7-day test: ~$8.40** | **Monthly: ~$36/mo** (AWS infra only, excludes Anthropic API plan)

See [COSTS.md](COSTS.md) for full breakdown with optimization options.

## References

- [OpenClaw Documentation](https://docs.openclaw.ai)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [GitHub Actions OIDC with AWS](https://docs.github.com/en/actions/security-for-github-actions/security-hardening-your-deployments/configuring-openid-connect-in-amazon-web-services)
- [Cloudflare R2 Remote Backend](https://developers.cloudflare.com/terraform/advanced-topics/remote-backend/)
- [AWS EC2 Pricing](https://aws.amazon.com/ec2/pricing/on-demand/)
