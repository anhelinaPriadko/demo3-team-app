# Latest Ubuntu 24.04 LTS (Noble) x86_64 from Canonical, used when no ami_id is given.
# The SSM agent is preinstalled on these images.

locals {
  ami_id = var.ami_id != null ? var.ami_id : data.aws_ami.ubuntu[0].id
}

resource "aws_instance" "this" {
  ami                         = local.ami_id
  instance_type               = var.instance_type
  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = var.security_group_ids
  iam_instance_profile        = var.iam_instance_profile
  associate_public_ip_address = false
  user_data                   = var.user_data

  root_block_device {
    volume_size           = var.root_volume_size
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  # IMDSv2 only
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = var.metadata_hop_limit
  }

  tags = merge(var.tags, {
    Name = var.name
  })

  lifecycle {
    # A newer "latest" AMI must not replace a running instance on the next plan
    ignore_changes = [ami]
  }
}

# Optional separate data volume (not formatted or mounted, do that in user_data)

resource "aws_ebs_volume" "data" {
  count = var.data_volume_size > 0 ? 1 : 0

  availability_zone = aws_instance.this.availability_zone
  size              = var.data_volume_size
  type              = "gp3"
  encrypted         = true

  tags = merge(var.tags, {
    Name = "${var.name}-data"
  })
}

resource "aws_volume_attachment" "data" {
  count = var.data_volume_size > 0 ? 1 : 0

  device_name = "/dev/sdf"
  volume_id   = aws_ebs_volume.data[0].id
  instance_id = aws_instance.this.id
}
