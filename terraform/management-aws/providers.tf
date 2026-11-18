provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Name = "demo3-aws-provider"
    }
  }
}   