output "db_instance_id" {
  description = "The ID of the RDS instance"
  value       = aws_db_instance.this.id
}

output "db_instance_arn" {
  description = "The ARN of the RDS instance"
  value       = aws_db_instance.this.arn
}

output "db_endpoint" {
  description = "The connection endpoint (hostname:port) of the RDS instance"
  value       = aws_db_instance.this.endpoint
}

output "db_address" {
  description = "The hostname of the RDS instance (without port)"
  value       = aws_db_instance.this.address
}

output "db_port" {
  description = "The port of the RDS instance"
  value       = aws_db_instance.this.port
}

output "db_name" {
  description = "The database name"
  value       = aws_db_instance.this.db_name
}

output "db_username" {
  description = "The master username"
  value       = aws_db_instance.this.username
}

output "db_master_password_secret_arn" {
  description = "ARN of the Secrets Manager secret containing the master password"
  value       = aws_secretsmanager_secret.db_master_password.arn
}

output "db_security_group_id" {
  description = "Security group ID for the RDS instance"
  value       = aws_security_group.rds.id
}

output "db_connection_url" {
  description = "Full PostgreSQL connection URL (sensitive)"
  value       = "postgresql://${aws_db_instance.this.username}:${random_password.db_master.result}@${aws_db_instance.this.address}:${aws_db_instance.this.port}/${aws_db_instance.this.db_name}?sslmode=require"
  sensitive   = true
}
