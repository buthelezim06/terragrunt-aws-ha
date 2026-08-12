terraform {
  source = "${get_repo_root()}/modules/ec2"
}

locals {
  env_vars = read_terragrunt_config(find_in_parent_folders("env.hcl"))
}

dependency "vpc" {
  config_path = "${get_terragrunt_dir()}/../vpc"

  mock_outputs = {
    vpc_id             = "vpc-mock"
    private_subnet_ids = ["subnet-mock-1", "subnet-mock-2"]
  }
  mock_outputs_allowed_terraform_commands = ["plan", "validate", "init"]
}

dependency "alb" {
  config_path = "${get_terragrunt_dir()}/../alb"

  mock_outputs = {
    alb_sg_id         = "sg-mock"
    target_group_arn  = "arn:aws:elasticloadbalancing:af-south-1:000000000000:targetgroup/mock/0000000000000000"
  }
  mock_outputs_allowed_terraform_commands = ["plan", "validate", "init"]
}

inputs = {
  environment         = local.env_vars.locals.environment
  vpc_id              = dependency.vpc.outputs.vpc_id
  private_subnet_ids  = dependency.vpc.outputs.private_subnet_ids
  alb_sg_id           = dependency.alb.outputs.alb_sg_id
  target_group_arn    = dependency.alb.outputs.target_group_arn
  instance_type       = local.env_vars.locals.instance_type
  instance_count      = 2
  tags = {
    Environment = local.env_vars.locals.environment
  }
}
