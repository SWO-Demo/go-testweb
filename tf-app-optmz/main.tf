data "aws_region" "current" {}
locals {
  az = "${data.aws_region.current.name}${var.aws_region_az}"
}
data "aws_vpc" "default" { default = true }
data "aws_subnet" "selected" {
  filter {
    name   = "availability-zone"
    values = [local.az]
  }

  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id] # Replace with your actual VPC ID
  }
}
