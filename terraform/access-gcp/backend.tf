terraform {
  backend "gcs" {
    bucket = "demo3-tfstate-gcp"
    prefix = "demo3/access"
  }
}
