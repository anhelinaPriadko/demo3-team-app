provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Name = "demo3-aws-provider"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.gcp_region

  default_labels = {
    project = "demo3"
  }
}
