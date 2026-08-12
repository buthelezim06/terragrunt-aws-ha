# Terragrunt: HA EC2 across 4 environments

Each environment gets its own VPC (single AWS account), an internet-facing
ALB, and 2 fixed EC2 instances spread across 2 AZs registered as ALB targets.

## Layout

```
modules/          # Reusable Terraform, no environment logic
  vpc/             # VPC, public+private subnets x2 AZs, IGW, NAT, routing
  alb/             # ALB, security group, target group, HTTP listener
  ec2/             # 2x EC2 in private subnets, registered to the ALB TG

live/              # Terragrunt: wires modules to real environments
  terragrunt.hcl   # Root: remote state (S3+DynamoDB) + AWS provider
  _envcommon/      # Shared config per component (source + inputs), env-agnostic
  dev/    env.hcl + vpc/alb/ec2 terragrunt.hcl (10.0.0.0/16)
  staging/env.hcl + vpc/alb/ec2 terragrunt.hcl (10.1.0.0/16)
  uat/    env.hcl + vpc/alb/ec2 terragrunt.hcl (10.2.0.0/16)
  prod/   env.hcl + vpc/alb/ec2 terragrunt.hcl (10.3.0.0/16)

scripts/
  bootstrap-backend.sh   # One-off: creates the S3 state bucket + lock table
  deploy.sh               # Wrapper: ./deploy.sh <env> <plan|apply|destroy>
```

Only `env.hcl` differs per environment (CIDR, instance size). Everything else
is inherited, so adding a 5th environment is one new folder + one env.hcl.

## How the dependency chain works

`ec2` depends on `alb` depends on `vpc`, declared via `dependency` blocks in
`_envcommon/*.hcl`. `terragrunt run-all apply` reads those and applies in the
right order automatically: vpc -> alb -> ec2.

## Usage

```bash
# one-time, per AWS account
./scripts/bootstrap-backend.sh

# plan / apply a whole environment
./scripts/deploy.sh dev plan
./scripts/deploy.sh dev apply

# target a single component
./scripts/deploy.sh dev apply vpc

# prod requires a typed "yes" confirmation before apply/destroy
./scripts/deploy.sh prod apply
```

Or drive Terragrunt directly from any `live/<env>/<component>` folder with
the normal `terragrunt plan` / `terragrunt apply`.

## Before first run

1. Edit `region` in `live/terragrunt.hcl` if not `eu-west-1`.
2. Edit the CIDR ranges in each `env.hcl` if `10.0-3.0.0.0/16` clash with
   anything else in the account.
3. Run `./scripts/bootstrap-backend.sh` once.
4. If you need SSH access, pass `key_name` as an extra input in the relevant
   `ec2/terragrunt.hcl`.

## Docker Swarm on these instances

Instance 0 in each environment bootstraps as the swarm **manager**; the rest
join as **workers**, using SSM Parameter Store to hand off the join token
(no SSH needed — see `modules/ec2/user_data.sh`).

- Deploy your stack once nodes are up: SSM into the manager
  (`aws ssm start-session --target <instance-id>`) and run
  `docker stack deploy -c docker-compose.yml <stack-name>`.
- The ALB target group forwards to port 80 on **both** instances. Swarm's
  routing mesh means every node answers on a published port and forwards
  internally to wherever the container actually is — so this works
  correctly even if a replica is only running on one of the two nodes.
- **Known limitation with only 2 nodes:** a single manager has no raft
  quorum, so if that instance is lost, running containers on the surviving
  worker keep serving traffic, but you lose the ability to reschedule or
  manage the cluster until the manager comes back. True HA for the swarm
  control plane needs 3 managers (odd number, for quorum). Worth adding a
  small 3rd manager-only instance before this carries real prod traffic —
  ask if you want that wired in.

## Notes / things to revisit for production

- VPC module uses a single NAT gateway per environment to control cost.
  For prod, consider one NAT per AZ (comment in `modules/vpc/main.tf` shows
  the change) so a NAT/AZ failure can't take out private subnet egress.
- ALB security group is open on 80/443 to `0.0.0.0/0` — tighten if this
  should sit behind a WAF/CDN or internal only.
- No HTTPS listener/cert wired up yet — add an `aws_lb_listener` on 443 with
  an ACM cert ARN once you have a domain.
- `enable_deletion_protection` is only turned on for prod.

<!-- GitHub Actions test -->
