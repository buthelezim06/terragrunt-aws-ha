locals {
  environment          = "dev"
  vpc_cidr             = "10.0.0.0/16"
  azs                  = ["af-south-1a", "af-south-1b"]
  public_subnet_cidrs  = ["10.0.0.0/24", "10.0.1.0/24"]
  private_subnet_cidrs = ["10.0.10.0/24", "10.0.11.0/24"]
  instance_type        = "t3.micro"
}
