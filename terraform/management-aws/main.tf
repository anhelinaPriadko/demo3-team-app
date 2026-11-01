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

  # additional_otlp_cidrs = ["10.20.0.0/16"]
}

module "iam" {
  source = "./modules/iam"
}

module "gitlab" {
  source = "./modules/ec2"

  name                 = "demo3-gitlab"
  instance_type        = "c7i-flex.large"
  subnet_id            = module.network.private_subnet_id
  availability_zone   = var.availability_zone
  security_group_ids   = [module.sg.gitlab_sg_id]
  iam_instance_profile = module.iam.gitlab_instance_profile
  root_volume_size     = 15
  data_volume_size     = 10

  user_data = templatefile("${path.module}/scripts/mount-data-volume.sh.tftpl", {
    mount_point = "/data"
    bind_mounts = {
      "gitlab-etc" = "/etc/gitlab"
      "gitlab-opt" = "/var/opt/gitlab"
    }
  })
}

module "signoz" {
  source = "./modules/ec2"

  name                 = "demo3-signoz"
  instance_type        = "c7i-flex.large"
  subnet_id            = module.network.private_subnet_id
  iam_instance_profile = module.iam.signoz_instance_profile
  security_group_ids   = [module.sg.signoz_sg_id]
  availability_zone   = var.availability_zone
  root_volume_size     = 15
  data_volume_size     = 10

  user_data = templatefile("${path.module}/scripts/mount-data-volume.sh.tftpl", {
    mount_point = "/data"
    bind_mounts = {
      "docker-volumes" = "/var/lib/docker/volumes"
    }
  })
}

module "runner" {
  source = "./modules/ec2"

  name                 = "demo3-runner"
  instance_type        = "t3.small"
  subnet_id            = module.network.private_subnet_id
  availability_zone   = var.availability_zone
  security_group_ids   = [module.sg.runner_sg_id]
  iam_instance_profile = module.iam.runner_instance_profile
  root_volume_size     = 15
  metadata_hop_limit   = 1
}