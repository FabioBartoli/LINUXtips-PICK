// Definindo apenas variáveis necessárias. Todo restante pode ser modificado diretamente neste arquivo
variable "access_key" {}
variable "secret_key" {}
variable "k8s_subnet_cidr" {
  default = "172.31.112.0/20" // Altere esse valor para o correspondente com sua VPC
}
variable "k8s_subnet_cidr_2" {
  default = "172.31.128.0/20" // Altere esse valor para o correspondente com sua VPC
}

provider "aws" {
  region     = "us-east-1"
  access_key = var.access_key
  secret_key = var.secret_key
}

terraform {
  backend "s3" {
    bucket = "fabiobartoli-k8s-pick-bucket" // Passe o nome do Bucket que você criou para armazenar o state
    key    = "terraform/k8s-PICK-state"
    region = "us-east-1"
  }
}

module "k8s_provisioner" {
  source           = "./modules/k8s_provisioner"
  ami              = "ami-04b70fa74e45c3917" // Ubuntu Server 24.04 LTS (HVM), SSD Volume Type
  cp_instance_type = "t2.micro" // 1vCPU x 1Gib Memory
  instance_type    = "t3a.small" // 2vCPU x 2Gib Memory
  volume_size           = 8
  instance_count        = 4                       // Número de instâncias
  vpc_id                = "vpc-096357cb7db323b17" // ID da sua VPC
  k8s_subnet_cidr       = var.k8s_subnet_cidr
  k8s_subnet_cidr_2     = var.k8s_subnet_cidr_2
  k8s_subnet_az         = "us-east-1a" // AZ para a subnet que será criada
  k8s_subnet_az_2       = "us-east-1b" // AZ para a subnet secundário para o Balancer
  AWS_ACCESS_KEY_ID     = var.access_key
  AWS_SECRET_ACCESS_KEY = var.secret_key
  private_key           = file("${path.module}/id_rsa")
  public_key            = file("${path.module}/id_rsa.pub")
  security_group_rules = [
    // PORTAS NECESSÁRIAS PARA O K8S
    {
      protocol    = "tcp"
      from_port   = 6443
      to_port     = 6443
      cidr_blocks = ["0.0.0.0/0"] //Acessar o Kubeconfig remotamente
    },
    {
      protocol    = "tcp"
      from_port   = 30443
      to_port     = 30443
      cidr_blocks = ["0.0.0.0/0"] //Acessar o Nodeport
    },
    //LIBERA TODAS PORTAS PRA COMUNICAÇÃO ENTRE O CLUSTER
    {
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      cidr_blocks = [var.k8s_subnet_cidr]
    }
  ]
}

output "control_plane_public_ip" {
  value = module.k8s_provisioner.control_plane_public_ip
}

output "worker_public_ips" {
  value = module.k8s_provisioner.worker_public_ips
}

output "k8s_alb_dns_name" {
  value = module.k8s_provisioner.k8s_alb_dns_name
}