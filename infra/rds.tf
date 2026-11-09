# Banco proprio do OS Service (database per service): instancia RDS separada
# da do monolito, para que nenhum outro servico leia ou escreva nas tabelas da
# OS. A integracao com os outros servicos e por API e mensageria, nunca por
# banco compartilhado.

# Subnets privadas (sem rota para a internet) provisionadas pelo stack de
# Kubernetes - aqui elas so viram um subnet group do RDS.
resource "aws_db_subnet_group" "os" {
  name       = "${local.name_prefix}-db-subnet-group"
  subnet_ids = local.db_subnet_ids

  tags = {
    Name = "${local.name_prefix}-db-subnet-group"
  }
}

resource "aws_security_group" "rds" {
  name        = "${local.name_prefix}-rds-sg"
  description = "SG do RDS do OS Service, so aceita trafego dos nos k3s"
  vpc_id      = local.vpc_id

  # Inclui o SG dos workers: o pod do OS Service pode ser agendado em qualquer
  # no do cluster. Os ids vem do state do stack de Kubernetes.
  ingress {
    description     = "SQL Server dos nos k3s (server + workers)"
    from_port       = 1433
    to_port         = 1433
    protocol        = "tcp"
    security_groups = local.k3s_node_sgids
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name_prefix}-rds-sg"
  }
}

resource "aws_db_instance" "os" {
  identifier     = local.name_prefix
  engine         = "sqlserver-ex"
  engine_version = var.db_engine_version
  license_model  = "license-included"

  instance_class    = var.db_instance_class
  allocated_storage = var.db_allocated_storage
  storage_type      = "gp3"

  # Criptografia em repouso com a chave gerenciada padrao da AWS (aws/rds).
  storage_encrypted = true

  username = var.db_master_username
  password = var.db_master_password

  db_subnet_group_name   = aws_db_subnet_group.os.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  multi_az            = false
  publicly_accessible = false

  backup_retention_period    = var.db_backup_retention_period
  auto_minor_version_upgrade = true
  copy_tags_to_snapshot      = true

  # Sem protecao contra exclusao nem snapshot final: projeto de estudo.
  deletion_protection = false
  skip_final_snapshot = true

  tags = {
    Name = "${local.name_prefix}-sqlserver"
  }
}
