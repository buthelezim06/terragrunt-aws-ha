variable "environment" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "private_subnet_ids" {
  description = "Needs at least 2 subnets (one per AZ) for HA placement"
  type        = list(string)
}

variable "alb_sg_id" {
  type = string
}

variable "target_group_arn" {
  type = string
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
}

variable "instance_count" {
  description = "Number of HA instances (default 2, one per AZ)"
  type        = number
  default     = 2
}

variable "key_name" {
  description = "Optional EC2 key pair name for SSH access"
  type        = string
  default     = null
}

variable "tags" {
  type    = map(string)
  default = {}
}
