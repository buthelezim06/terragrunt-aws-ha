# Root config, included by every environment/component below it.
# Centralises remote state + provider config so nothing downstream repeats it.

locals {
  region = "af-south-1"
}

remote_state {
  backend = "s3"
  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }
  config = {
    bucket         = "acme-terraform-state-${get_aws_account_id()}"
    key            = "${path_relative_to_include()}/terraform.tfstate"
    region         = local.region
    encrypt        = true
    use_lockfile   = true
  }
}

generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<PROVIDEREOF
provider "aws" {
  region = "${local.region}"
  default_tags {
    tags = {
      ManagedBy = "terragrunt"
    }
  }
}
PROVIDEREOF
}
