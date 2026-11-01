resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  instance_tenancy     = "default"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "demo3-vpc"
  }
}

# subnets

resource "aws_subnet" "pub_subnet" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.public_subnet_cidr
  availability_zone = var.availability_zone

  tags = {
    Name = "demo3-public-subnet"
  }
}

resource "aws_subnet" "pr_subnet" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidr
  availability_zone = var.availability_zone

  tags = {
    Name = "demo3-private-subnet"
  }
}

# gateways

resource "aws_eip" "nat" {
  domain = "vpc"
  tags = {
    Name = "demo3-eip-nat"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "demo3-internet-gateway"
  }
}

resource "aws_nat_gateway" "nat" {
  subnet_id     = aws_subnet.pub_subnet.id
  allocation_id = aws_eip.nat.id

  tags = {
    Name = "demo3-nat-gateway"
  }

  depends_on = [aws_internet_gateway.igw]
}

# route tables

resource "aws_route_table" "pub_rtb" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "demo3-public-route-table"
  }
}

resource "aws_route_table" "pr_rtb" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "demo3-private-route-table"
  }
}

resource "aws_route" "igw_route" {
  route_table_id         = aws_route_table.pub_rtb.id
  gateway_id             = aws_internet_gateway.igw.id
  destination_cidr_block = "0.0.0.0/0"
}

resource "aws_route_table_association" "pub_rtb" {
  route_table_id = aws_route_table.pub_rtb.id
  subnet_id      = aws_subnet.pub_subnet.id
}



resource "aws_route" "nat_route" {
  route_table_id         = aws_route_table.pr_rtb.id
  nat_gateway_id         = aws_nat_gateway.nat.id
  destination_cidr_block = "0.0.0.0/0"
}

resource "aws_route_table_association" "pr_rtb" {
  route_table_id = aws_route_table.pr_rtb.id
  subnet_id      = aws_subnet.pr_subnet.id
}

