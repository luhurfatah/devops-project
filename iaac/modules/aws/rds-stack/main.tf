# ─── RDS Stack Module ─────────────────────────────────────────
# Self-contained module provisioning RDS PostgreSQL with
# AWS Secrets Manager for master password management.
# Depends on a VPC stack being deployed first.

locals {
  name_prefix = "${var.project_name}-${var.environment}"
  common_tags = merge({
    Environment = var.environment
    Project     = var.project_name
    ManagedBy   = "terraform"
  }, var.tags)
}

# ─── Master Password ──────────────────────────────────────────
resource "random_password" "db_master" {
  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "aws_secretsmanager_secret" "db_master_password" {
  name                    = "${local.name_prefix}-rds-master-password"
  recovery_window_in_days = 0

  tags = local.common_tags
}

resource "aws_secretsmanager_secret_version" "db_master_password" {
  secret_id     = aws_secretsmanager_secret.db_master_password.id
  secret_string = random_password.db_master.result
}

# ─── DB Subnet Group ──────────────────────────────────────────
resource "aws_db_subnet_group" "this" {
  name       = "${local.name_prefix}-rds-subnet-group"
  subnet_ids = var.private_subnet_ids

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-rds-subnet-group"
  })
}

# ─── Security Group ───────────────────────────────────────────
resource "aws_security_group" "rds" {
  name        = "${local.name_prefix}-rds-sg"
  description = "Security group for RDS PostgreSQL"
  vpc_id      = var.vpc_id

  ingress {
    description = "PostgreSQL from VPC"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr_block]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-rds-sg"
  })
}

# ─── DB Parameter Group ───────────────────────────────────────
resource "aws_db_parameter_group" "this" {
  name   = "${local.name_prefix}-rds-pg-params"
  family = "postgres${var.engine_version}"

  tags = local.common_tags
}

# ─── RDS Instance ─────────────────────────────────────────────
resource "aws_db_instance" "this" {
  identifier = "${local.name_prefix}-rds"

  engine         = "postgres"
  engine_version = var.engine_version
  instance_class = var.instance_class

  allocated_storage = var.allocated_storage
  storage_type      = var.storage_type
  storage_encrypted = true

  db_name  = var.db_name
  username = var.db_username
  password = random_password.db_master.result
  port     = 5432

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  parameter_group_name   = aws_db_parameter_group.this.name

  multi_az                = var.multi_az
  publicly_accessible     = false
  skip_final_snapshot     = var.skip_final_snapshot
  backup_retention_period = var.backup_retention_period
  backup_window           = var.backup_window
  maintenance_window      = var.maintenance_window
  deletion_protection     = var.deletion_protection

  auto_minor_version_upgrade      = true
  enabled_cloudwatch_logs_exports = ["postgresql"]

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-rds"
  })
}
