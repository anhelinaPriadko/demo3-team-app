locals {
  bucket_name = "${var.name_prefix}-app-${var.project_id}"
}

data "google_service_account" "vm" {
  for_each   = toset(["nginx", "app", "db", "etcd"])
  account_id = "${var.name_prefix}-${each.key}-sa"
}

locals {
  vm_sa_email = { for k, sa in data.google_service_account.vm : k => sa.email }

  app_zone = {
    for i in range(var.app_count) : "app-${i + 1}" => var.app_zones[i % length(var.app_zones)]
  }
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

  management_cidr = var.management_cidr
}

module "storage" {
  source = "./modules/storage"

  name         = local.bucket_name
  location     = var.region
  app_sa_email = local.vm_sa_email["app"]
  db_sa_email  = local.vm_sa_email["db"]
}

module "nginx" {
  source = "./modules/compute"

  name                  = "${var.name_prefix}-nginx"
  machine_type          = "e2-small"
  zone                  = var.zone
  subnet_self_link      = module.network.public_subnet_self_link
  network_tags          = ["web"]
  service_account_email = local.vm_sa_email["nginx"]
  external_ip           = true
}

module "app" {
  source   = "./modules/compute"
  for_each = local.app_zone

  name                  = "${var.name_prefix}-${each.key}"
  machine_type          = "e2-small"
  zone                  = each.value
  subnet_self_link      = module.network.private_subnet_self_link
  network_tags          = ["app"]
  service_account_email = local.vm_sa_email["app"]
  reserve_internal_ip   = true
}

module "db_master" {
  source = "./modules/compute"

  name                  = "${var.name_prefix}-db-master"
  machine_type          = "e2-medium"
  zone                  = var.zone
  subnet_self_link      = module.network.private_subnet_self_link
  network_tags          = ["db"]
  service_account_email = local.vm_sa_email["db"]
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
  service_account_email = local.vm_sa_email["db"]
  reserve_internal_ip   = true
  data_disk_size        = var.db_data_disk_size

  startup_script = templatefile("${path.module}/scripts/mount-data-volume.sh.tftpl", {
    mount_point = "/data"
    bind_mounts = {
      "postgresql" = "/var/lib/postgresql"
    }
  })
}

module "db_witness" {
  source = "./modules/compute"

  name                  = "${var.name_prefix}-db-witness"
  machine_type          = "e2-small"
  zone                  = var.witness_zone
  subnet_self_link      = module.network.private_subnet_self_link
  network_tags          = ["etcd"]
  service_account_email = local.vm_sa_email["etcd"]
  reserve_internal_ip   = true
}

# DNS records in the public zone created by access-gcp: the domain and www point to Nginx

data "google_dns_managed_zone" "public" {
  name = "${var.name_prefix}-public"
}

resource "google_dns_record_set" "web" {
  for_each = {
    apex = ""
    www  = "www."
  }

  managed_zone = data.google_dns_managed_zone.public.name
  name         = "${each.value}${data.google_dns_managed_zone.public.dns_name}"
  type         = "A"
  ttl          = 300
  rrdatas      = [module.nginx.public_ip]
}
