locals {
  environment          = "staging"
  vpc_cidr             = "10.1.0.0/16"
  azs                  = ["af-south-1a", "af-south-1b"]
  public_subnet_cidrs  = ["10.1.0.0/24", "10.1.1.0/24"]
  private_subnet_cidrs = ["10.1.10.0/24", "10.1.11.0/24"]
  instance_type        = "t3.micro"
}
