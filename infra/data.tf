# A rede (VPC, subnets de banco) e os security groups dos nos k3s pertencem ao
# stack compartilhado de Kubernetes (repositorio InfraKubernete). Este stack so
# le os outputs do state remoto - nao trava nem grava nada no state de la.
data "terraform_remote_state" "kubernetes" {
  backend = "s3"

  config = {
    bucket = var.kubernetes_state_bucket
    key    = var.kubernetes_state_key
    region = var.aws_region
  }
}

locals {
  vpc_id        = data.terraform_remote_state.kubernetes.outputs.vpc_id
  db_subnet_ids = data.terraform_remote_state.kubernetes.outputs.db_subnet_ids
  k3s_node_sgids = [
    data.terraform_remote_state.kubernetes.outputs.ec2_security_group_id,
    data.terraform_remote_state.kubernetes.outputs.worker_security_group_id,
  ]

  # Tudo do OS Service fica com nome e prefixo SSM proprios, separados dos do
  # monolito (/mechanicltda/prod/...): cada servico so le o seu prefixo.
  name_prefix     = "${var.project_name}-${var.environment}-${var.service_name}"
  ssm_path_prefix = "/${var.project_name}/${var.environment}/${var.service_name}"
}
