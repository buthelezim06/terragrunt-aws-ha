locals {
  environment          = "prod"
  vpc_cidr             = "10.3.0.0/16"
  azs                  = ["af-south-1a", "af-south-1b"]
  public_subnet_cidrs  = ["10.3.0.0/24", "10.3.1.0/24"]
  private_subnet_cidrs = ["10.3.10.0/24", "10.3.11.0/24"]
  instance_type        = "t3.medium"
}
