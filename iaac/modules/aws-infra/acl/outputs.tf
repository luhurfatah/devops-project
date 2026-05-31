output "public_network_acl_id" {
  description = "The ID of the public network ACL"
  value       = aws_network_acl.public.id
}

output "private_network_acl_id" {
  description = "The ID of the private network ACL"
  value       = aws_network_acl.private.id
}

output "public_network_acl_arn" {
  description = "The ARN of the public network ACL"
  value       = aws_network_acl.public.arn
}

output "private_network_acl_arn" {
  description = "The ARN of the private network ACL"
  value       = aws_network_acl.private.arn
}