output "vpc_id" {
  description = "ID of the management VPC"
  value       = aws_vpc.main.id
}

output "vpc_cidr" {
  description = "CIDR block of the management VPC"
  value       = aws_vpc.main.cidr_block
}

output "public_subnet_id" {
  description = "ID of the public subnet (holds the NAT Gateway)"
  value       = aws_subnet.pub_subnet.id
}

output "private_subnet_id" {
  description = "ID of the private subnet (holds the instances)"
  value       = aws_subnet.pr_subnet.id
}

output "private_route_table_id" {
  description = "ID of the private route table, used later to add the route to GCP over the VPN"
  value       = aws_route_table.pr_rtb.id
}

output "nat_public_ip" {
  description = "Elastic IP of the NAT Gateway, the source address of all outbound traffic"
  value       = aws_eip.nat.public_ip
}
