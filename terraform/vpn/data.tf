# Outputs of the two other roots

data "terraform_remote_state" "aws" {
  backend = "s3"

  config = {
    bucket = "demo3-tfstate-mgmt-bucket"
    key    = "demo3/terraform.tfstate"
    region = "eu-central-1"
  }
}

data "terraform_remote_state" "gcp" {
  backend = "gcs"

  config = {
    bucket = "demo3-tfstate-gcp"
    prefix = "demo3/application"
  }
}
