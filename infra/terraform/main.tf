locals {
  name = var.project
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.8.1"

  name = local.name
  cidr = "10.0.0.0/16"

  azs             = ["${var.aws_region}a","${var.aws_region}b","${var.aws_region}c"]
  private_subnets = ["10.0.1.0/24","10.0.2.0/24","10.0.3.0/24"]
  public_subnets  = ["10.0.101.0/24","10.0.102.0/24","10.0.103.0/24"]

  enable_nat_gateway = true
  single_nat_gateway = true

  tags = { Project = local.name }
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "20.24.1"

  cluster_name    = "${local.name}-eks"
  cluster_version = "1.29"
  vpc_id          = module.vpc.vpc_id
  subnet_ids      = module.vpc.private_subnets

  enable_irsa = true

  eks_managed_node_groups = {
    default = {
      instance_types = ["t3.small"]
      desired_size   = 2
      min_size       = 2
      max_size       = 4
    }
  }

  tags = { Project = local.name }
}

# IAM role for AWS Load Balancer Controller
module "alb_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "5.39.1"

  role_name                              = "${local.name}-alb-irsa"
  attach_load_balancer_controller_policy = true
  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-load-balancer-controller"]
    }
  }
}

# ECR for the app
resource "aws_ecr_repository" "app" {
  name = "${local.name}-repo"
  image_scanning_configuration { scan_on_push = true }
  force_delete = true
  tags = { Project = local.name }
}

# DynamoDB table for todos
resource "aws_dynamodb_table" "todos" {
  name         = "${local.name}-todos"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }

  tags = { Project = local.name }
}

# IRSA role for the app to access DynamoDB
module "app_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "5.39.1"

  role_name = "${local.name}-app-irsa"
  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["todo:todo-api-sa"]
    }
  }

  inline_policy_statements = [{
    sid    = "DynamoAccess"
    effect = "Allow"
    actions = [
      "dynamodb:PutItem",
      "dynamodb:GetItem",
      "dynamodb:UpdateItem",
      "dynamodb:DeleteItem",
      "dynamodb:Scan"
    ]
    resources = [aws_dynamodb_table.todos.arn]
  }]
}

# Kubernetes namespace and SA for app (via Terraform Kubernetes provider)
provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  token                  = data.aws_eks_cluster_auth.this.token
}

data "aws_eks_cluster_auth" "this" {
  name = module.eks.cluster_name
}

resource "kubernetes_namespace" "todo" {
  metadata { name = "todo" }
}

resource "kubernetes_service_account" "todo_api" {
  metadata {
    name      = "todo-api-sa"
    namespace = kubernetes_namespace.todo.metadata[0].name
    annotations = {
      "eks.amazonaws.com/role-arn" = module.app_irsa.iam_role_arn
    }
  }
}

# Optional: output IRSA for Helm values
output "app_irsa_role_arn" {
  value = module.app_irsa.iam_role_arn
}
