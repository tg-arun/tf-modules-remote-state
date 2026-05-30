# tf-modules-remote-state

> Reusable Terraform modules with S3 remote state backend —
> the foundation of how every production engineering team
> manages infrastructure at scale.

---

## What this project solves

Most teams hit three problems as they grow with Terraform:

| Problem | Without this project | With this project |
|---|---|---|
| Code duplication | VPC code copy-pasted per environment | One module called from everywhere |
| State corruption | Two engineers apply at the same time → broken state | S3 native locking prevents concurrent applies |
| Lost state | State lives on someone's laptop, they leave | State in S3, versioned, encrypted, accessible to whole team |

---

## Architecture


tf-modules-remote-state/
│
├── bootstrap/                  # Run once — creates the backend infrastructure
│   ├── main.tf
│   ├── variables.tf
│   └── terraform.tfvars
│
├── modules/                    # Reusable building blocks
│   ├── vpc/                    # VPC module — call from any environment
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   └── s3-backend/             # Creates S3 bucket + lock for state storage
│       ├── main.tf
│       ├── variables.tf
│       └── outputs.tf
│
└── environments/               # Where infrastructure actually gets deployed
├── dev/                    # 2 AZs, no NAT gateway (cost saving)
│   ├── main.tf
│   ├── backend.tf
│   ├── variables.tf
│   └── terraform.tfvars
└── prod/                   # 3 AZs, NAT gateway enabled (high availability)
├── main.tf
├── backend.tf
├── variables.tf
└── terraform.tfvars


---

## What gets created

### Bootstrap (one-time)
- S3 bucket — stores all Terraform state files, versioning enabled,
  encrypted at rest, all public access blocked
- `prevent_destroy = true` on both resources — protects against
  accidental deletion

### VPC module (called per environment)
- VPC with DNS hostnames enabled
- Public subnets — one per AZ, auto-assigns public IPs
- Private subnets — one per AZ, no public access
- Internet Gateway — public subnet internet access
- NAT Gateway — optional, controlled by `enable_nat_gateway` variable
- Route tables — public routes to IGW, private routes to NAT
- VPC Flow Logs — captures all traffic metadata to CloudWatch,
  30-day retention

### Per environment
| Resource | Dev | Prod |
|---|---|---|
| Availability Zones | 2 | 3 |
| NAT Gateway | ❌ disabled | ✅ enabled |
| VPC CIDR | 10.0.0.0/16 | 10.1.0.0/16 |
| State location | s3://bucket/dev/vpc/terraform.tfstate | s3://bucket/prod/vpc/terraform.tfstate |

---

## Key concepts

### Modules
A module is a reusable folder of Terraform code that accepts inputs
and returns outputs — like a function in programming.

```hcl
# Both environments call the same module with different values
module "vpc" {
  source = "../../modules/vpc"

  environment        = "prod"
  vpc_cidr           = "10.1.0.0/16"
  az_count           = 3
  enable_nat_gateway = true
}
```

Without modules you copy-paste 200 lines of VPC code per environment.
With modules you write it once and enforce standards everywhere.

### Remote state
By default Terraform stores state locally. In a team that means:
- Engineer A applies from their laptop
- Engineer B applies from their laptop at the same time
- Both write to the same state → corruption

Remote state moves the file to S3. The `use_lockfile = true` setting
creates a `.tflock` file in S3 during apply — any concurrent apply
sees the lock and fails with a clear error instead of corrupting state.

```hcl
terraform {
  backend "s3" {
    bucket       = "myproject-tfstate-123456789012"
    key          = "prod/vpc/terraform.tfstate"
    region       = "ap-south-1"
    use_lockfile = true   # S3 native locking — no DynamoDB needed in v5.100+
    encrypt      = true
  }
}
```

### Bootstrap chicken-and-egg problem
You need Terraform to create the S3 bucket, but you need the S3 bucket
to store Terraform state. The solution: bootstrap runs with local state
intentionally (one time only) to create the backend infrastructure.
After that, every other environment uses remote state.

### cidrsubnet() — dynamic CIDR calculation
Subnet CIDRs are calculated automatically instead of hardcoded:

```hcl
# cidrsubnet("10.0.0.0/16", 8, 0) = "10.0.0.0/24"
# cidrsubnet("10.0.0.0/16", 8, 1) = "10.0.1.0/24"
cidr_block = cidrsubnet(var.vpc_cidr, 8, count.index)
```

Change `az_count` from 2 to 3 and a third subnet appears automatically.
No manual CIDR management.

### Non-overlapping CIDRs across environments
Dev uses `10.0.0.0/16`, prod uses `10.1.0.0/16`. They must never
overlap — if you connect them later via VPC peering or Transit Gateway,
overlapping CIDRs cause routing conflicts that are painful to fix.

---

## Prerequisites

- Terraform >= 1.6
- AWS CLI configured (`aws configure`)
- AWS account ID (run `aws sts get-caller-identity --query Account --output text`)

---

## Deploy

### 1. Bootstrap — run once

```bash
cd bootstrap
cp terraform.tfvars.example terraform.tfvars
# fill in project_name, aws_region, aws_account_id

terraform init
terraform apply

# Note the outputs — you need the bucket name for next steps
terraform output state_bucket_name
```

### 2. Deploy dev

```bash
cd environments/dev
cp terraform.tfvars.example terraform.tfvars
# fill in your values
# update backend.tf with your bucket name from bootstrap output

terraform init
terraform plan    # always read this before applying
terraform apply
```

### 3. Deploy prod

```bash
cd environments/prod
cp terraform.tfvars.example terraform.tfvars
# use a different vpc_cidr from dev (e.g. 10.1.0.0/16)
# update backend.tf with your bucket name

terraform init
terraform plan
terraform apply
```

### 4. Verify state files in S3

```bash
aws s3 ls s3://YOUR_BUCKET_NAME/ --recursive

# Expected output:
# dev/vpc/terraform.tfstate
# prod/vpc/terraform.tfstate
```

---

## Cost

| Resource | Cost |
|---|---|
| S3 state storage | ~$0.00 (state files are tiny) |
| VPC, subnets, IGW, route tables | Free |
| NAT Gateway (prod only) | ~$32/month |
| CloudWatch Flow Logs | ~$0.50/month |

**Destroy prod when not in use** — NAT Gateway is the only real cost.

```bash
cd environments/prod && terraform destroy
cd environments/dev  && terraform destroy
# Do NOT destroy bootstrap — the S3 bucket is needed for future projects
```

---

## What I learned

- **Modules enforce standards** — every VPC created through this module
  automatically gets flow logs, consistent tagging, and correct route
  table associations. Engineers can't forget them.

- **Remote state is a team contract** — local state works for one person.
  The moment two people touch the same infrastructure, you need remote
  state with locking. This is one of the first things a new company
  sets up.

- **Bootstrap is intentionally local** — the state backend can't store
  its own state. Running bootstrap with local state once to create the
  S3 bucket is the standard pattern. After that, everything uses remote.

- **S3 native locking vs DynamoDB** — AWS provider v5.100 introduced
  `use_lockfile = true` which stores lock files directly in S3.
  Previously you needed a separate DynamoDB table just for locking.
  Simpler and cheaper.

- **`prevent_destroy` on critical resources** — the state bucket and
  lock table have `lifecycle { prevent_destroy = true }`. If someone
  runs `terraform destroy` on bootstrap, Terraform refuses. Losing your
  state bucket means losing the record of all your infrastructure.

- **Separate state files per environment** — same S3 bucket but
  different keys (`dev/vpc/terraform.tfstate` vs
  `prod/vpc/terraform.tfstate`). A `terraform destroy` in dev never
  touches prod. Complete blast radius isolation.

- **`count` vs `for_each`** — used `count` for subnets because they're
  indexed by number. `for_each` is better when items have meaningful
  names (like security group rules). Knowing when to use which is a
  common interview question.

- **Non-overlapping VPC CIDRs** — planned for future VPC peering by
  giving dev and prod different CIDR blocks from day one. Fixing
  overlapping CIDRs after peering is set up is a painful migration.

---

## Interview talking points

### "How do you manage Terraform state in a team?"
State lives in S3 with versioning enabled — we can restore any
previous version if an apply corrupts it. S3 native locking
(`use_lockfile = true` in provider v5.100+) prevents concurrent
applies. The state file is encrypted at rest. Nobody runs Terraform
from their laptop against production — state is centralised and
the team has equal access.

### "How do you reuse Terraform code across environments?"
We use modules. The VPC module is written once and called from dev,
staging, and prod with different input values. Dev uses 2 AZs and
no NAT gateway to save ~$32/month. Prod uses 3 AZs and NAT for
high availability. The module enforces standards — flow logs are
always on, tagging is automatic, no engineer can forget them.

### "What's the difference between your dev and prod environments?"
Same module, different inputs. Dev: 2 AZs, no NAT, CIDR 10.0.0.0/16.
Prod: 3 AZs, NAT enabled, CIDR 10.1.0.0/16. CIDRs are intentionally
non-overlapping so we can peer them later without conflicts. State
files are completely isolated — a destroy in dev cannot touch prod.

### "What is the bootstrap problem in Terraform?"
You need Terraform to create the S3 bucket for remote state, but you
need S3 to store Terraform state — a chicken-and-egg problem. The
solution is to run bootstrap once with local state to create the
backend infrastructure. After that, all other environments use remote
state. The bootstrap state file stays local and is gitignored.

### "What happens if two engineers run terraform apply at the same time?"
With local state, both writes happen and one overwrites the other —
state corruption. With S3 remote state and locking enabled, the first
apply writes a `.tflock` file to S3. The second apply sees the lock
and immediately fails with a clear error message showing who holds
the lock and when it was acquired. When the first apply finishes,
the lock is released automatically.

### "Why does your VPC module use count instead of for_each for subnets?"
Count works well here because subnets are identical except for their
index — the CIDR and AZ are calculated from the index using
`cidrsubnet()` and `local.azs[count.index]`. For_each is better when
resources have meaningful unique keys, like iterating over a map of
security group rules where each rule has a name. Using count on
subnets keeps the code simple and the plan output easy to read.

---

## Part of my Terraform learning series

| # | Project | Status |
|---|---|---|
| 1 | Static website — S3 + CloudFront + Route53 | ✅ Complete |
| 2 | CloudWatch alarm automation — Lambda + EventBridge | ✅ Complete |
| 3 | Modules + remote state | ✅ Complete |
| 4 | ECS + ALB + Auto Scaling | 🔜 Coming soon |
| 5 | CI/CD pipeline — GitHub Actions + Terraform | 🔜 Coming soon |



