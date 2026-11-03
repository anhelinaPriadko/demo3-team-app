locals {
  bucket_name = "${var.name_prefix}-app-${var.project_id}"
}

module "network" {
  source = "./modules/network"

  name_prefix         = var.name_prefix
  region              = var.region
  public_subnet_cidr  = var.public_subnet_cidr
  private_subnet_cidr = var.private_subnet_cidr
}

module "firewall" {
  source = "./modules/firewall"

  name_prefix = var.name_prefix
  network     = module.network.network_name
  app_port    = var.app_port
}

module "storage" {
  source = "./modules/storage"

  name     = local.bucket_name
  location = var.region
}

module "iam" {
  source = "./modules/iam"

  name_prefix = var.name_prefix
  bucket_name = module.storage.bucket_name
}

module "nginx" {
  source = "./modules/compute"

  name                  = "${var.name_prefix}-nginx"
  machine_type          = "e2-small"
  zone                  = var.zone
  subnet_self_link      = module.network.public_subnet_self_link
  network_tags          = ["web"]
  service_account_email = module.iam.nginx_sa_email
  external_ip           = true
}

module "app" {
  source = "./modules/compute"

  name                  = "${var.name_prefix}-app"
  machine_type          = "e2-medium"
  zone                  = var.zone
  subnet_self_link      = module.network.private_subnet_self_link
  network_tags          = ["app"]
  service_account_email = module.iam.app_sa_email
  reserve_internal_ip   = true
}

module "db_master" {
  source = "./modules/compute"

  name                  = "${var.name_prefix}-db-master"
  machine_type          = "e2-medium"
  zone                  = var.zone
  subnet_self_link      = module.network.private_subnet_self_link
  network_tags          = ["db"]
  service_account_email = module.iam.db_sa_email
  reserve_internal_ip   = true
  data_disk_size        = var.db_data_disk_size

  startup_script = templatefile("${path.module}/scripts/mount-data-volume.sh.tftpl", {
    mount_point = "/data"
    bind_mounts = {
      "postgresql" = "/var/lib/postgresql"
    }
  })
}

module "db_slave" {
  source = "./modules/compute"

  name                  = "${var.name_prefix}-db-slave"
  machine_type          = "e2-medium"
  zone                  = var.zone
  subnet_self_link      = module.network.private_subnet_self_link
  network_tags          = ["db"]
  service_account_email = module.iam.db_sa_email
  reserve_internal_ip   = true
  data_disk_size        = var.db_data_disk_size

  startup_script = templatefile("${path.module}/scripts/mount-data-volume.sh.tftpl", {
    mount_point = "/data"
    bind_mounts = {
      "postgresql" = "/var/lib/postgresql"
    }
  })
}
