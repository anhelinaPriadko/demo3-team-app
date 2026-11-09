terraform {
  backend "s3" {
    bucket       = "demo3-tfstate-mgmt-bucket"
    key          = "demo3/terraform.tfstate"
    region       = "eu-central-1"
    encrypt      = true
    use_lockfile = true
  }
}