module "network" {
  source = "./modules/network"

  availability_zone   = var.availability_zone
  vpc_cidr            = var.vpc_cidr
  public_subnet_cidr  = var.public_subnet_cidr
  private_subnet_cidr = var.private_subnet_cidr
}

module "sg" {
  source = "./modules/sg"

  vpc_id   = module.network.vpc_id
  vpc_cidr = module.network.vpc_cidr

  # later, after the VPN:
  # additional_otlp_cidrs = ["10.20.0.0/16"]
}