# OrdemServico-InfraSGBD — Banco de Dados do OS Service

Terraform do **RDS SQL Server próprio do OS Service** (microsserviço de Ordem de Serviço da Fase 4):
instância, subnet group, security group e a connection string publicada no SSM Parameter Store.

Cada microsserviço tem o seu banco (*database per service*): nenhum outro serviço acessa as tabelas
da OS. A integração com o monolito, o Billing e a Execução é por API e mensageria (Saga), nunca por
banco compartilhado.

## Os três repositórios do OS Service

| # | Repositório | Conteúdo | CI/CD |
|---|---|---|---|
| 1 | [OrdemServico-service](https://github.com/Fiap-Mecanic-Ltda/OrdemServico-service) | API .NET 9 do OS Service + Saga | build, testes, cobertura e push da imagem no ECR |
| 2 | [OrdemServico-InfraKubernete](https://github.com/Fiap-Mecanic-Ltda/OrdemServico-InfraKubernete) | ECR, IAM/OIDC, rota no ALB + manifestos `k8s/` | `terraform plan/apply` + deploy no k3s |
| 3 | **OrdemServico-InfraSGBD** (este) | Terraform do RDS SQL Server da OS | `terraform plan/apply` |

O cluster k3s, a VPC e o ALB continuam no repositório compartilhado
[InfraKubernete](https://github.com/Fiap-Mecanic-Ltda/InfraKubernete).

## Como este stack conversa com os outros

```text
InfraKubernete (state prod/terraform.tfstate)
   │  outputs: vpc_id, db_subnet_ids, ec2_security_group_id, worker_security_group_id
   ▼  (terraform_remote_state, somente leitura)
OrdemServico-InfraSGBD (state prod/os-sgbd/terraform.tfstate)
   │  cria: db subnet group, SG do RDS, instância RDS mechanicltda-prod-os
   │  publica: /mechanicltda/prod/os/db-connection-string (SecureString)
   ▼
pods do OS Service no k3s leem a connection string do SSM a cada deploy
```

- **Não cria rede**: VPC e subnets pertencem ao InfraKubernete, que precisa estar aplicado antes.
- **Não conhece a aplicação**: o contrato é o parâmetro do SSM. Nenhuma senha trafega em YAML
  versionado.
- **Não cria o schema**: a API aplica as migrations do EF Core no boot (banco `OsServiceDb`,
  schema `os`, incluindo as tabelas da Saga e do outbox/inbox do MassTransit).
- O SG do RDS só aceita a porta 1433 vinda dos nós do k3s (server e workers).

## Estrutura

```text
OrdemServico-InfraSGBD/
├── infra/
│   ├── versions.tf              # backend S3 (chave prod/os-sgbd/terraform.tfstate) e provider
│   ├── data.tf                  # terraform_remote_state do InfraKubernete + locals
│   ├── variables.tf             # project/environment/service e parâmetros do banco
│   ├── rds.tf                   # subnet group, security group e a instância RDS
│   ├── ssm.tf                   # connection string (SecureString) no Parameter Store
│   └── outputs.tf               # endereço do RDS, SG e nome do parâmetro SSM
└── .github/workflows/terraform.yml
```

## Rodando localmente

```bash
cd infra
cp terraform.tfvars.example terraform.tfvars   # preencher com valores reais (nunca commitar)
terraform init
terraform plan
terraform apply
```

## Secrets necessários no repositório GitHub

(Settings → Secrets and variables → Actions)

| Nome | Tipo | Uso |
|---|---|---|
| `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` | Secret | Chave do `terraform-deployer` (também lê o state remoto do InfraKubernete) |
| `SA_PASSWORD` | Secret | `TF_VAR_db_master_password` — senha master do RDS da OS |

O Environment `production` precisa existir para o job de `apply`. `db_engine_version` está fixado
no workflow (`15.00.4430.1.v1`), e `aws_region`/`project_name`/`environment` saem dos defaults de
`infra/variables.tf`.

## Fluxo de trabalho no Git

Mudanças entram por branch `feature/...` com Pull Request para **`homologacao`**, e a `main`
recebe a `homologacao` por Pull Request. Nada é commitado direto nas duas.

| Branch | O que roda (quando `infra/**` muda) |
|---|---|
| PR para `homologacao` ou `main` | `plan` |
| push em `homologacao` | `plan` — não há ambiente de homologação na AWS |
| push em `main` | `plan` e **`apply` automático** no Environment `production` |

**Trava de publicação:** o `apply` (automático ou manual) só roda com a Repository Variable
`PUBLICAR_AWS=true` (Settings → Secrets and variables → Actions → Variables). Sem ela, a `main`
roda apenas o `plan` e nada é criado na AWS.

O `apply` manual (`workflow_dispatch`) só roda a partir da `main`. Configure revisores obrigatórios
no Environment `production`: recriar o RDS apaga os dados (sem snapshot final neste projeto).

## Custo

É uma segunda instância `db.t3.micro` SQL Server Express. Para economizar créditos fora das
apresentações, rode `terraform destroy` aqui (o InfraKubernete não depende deste stack) e aplique
de novo quando precisar: a API recria o schema no próximo boot.
