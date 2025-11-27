output "aws_region" { value = var.aws_region }
output "vpc_id" { value = module.vpc.vpc_id }
output "eks_cluster_name" { value = module.eks.cluster_name }
output "ecr_repository_url" { value = aws_ecr_repository.app.repository_url }
output "dynamodb_table_name" { value = aws_dynamodb_table.todos.name }
