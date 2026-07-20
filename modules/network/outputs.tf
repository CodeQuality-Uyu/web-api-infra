output "vpc_id" {
  value = aws_vpc.this.id
}

output "vpc_cidr" {
  value = aws_vpc.this.cidr_block
}

output "public_subnet_ids" {
  value = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  value = aws_subnet.private[*].id
}

output "db_clients_sg_id" {
  value = aws_security_group.db_clients.id
}

output "bastion_sg_id" {
  value       = var.enable_bastion ? aws_security_group.bastion[0].id : null
  description = "SG of the SSM bastion (RDS allows this so you can tunnel in)."
}

output "bastion_instance_id" {
  value       = var.enable_bastion ? aws_instance.bastion[0].id : null
  description = "Bastion instance id for aws ssm start-session."
}

output "nat_eip" {
  description = "Public egress IP (NAT gateway EIP). Allowlist this on a public RDS in another account so this VPC's App Runner can reach it."
  value       = var.enable_nat ? aws_eip.nat[0].public_ip : null
}
