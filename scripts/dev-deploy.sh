#!/usr/bin/env bash
set -euo pipefail
NS=todo
APP=todo-api
ECR_URL=$(terraform -chdir=infra/terraform output -raw ecr_repository_url)
TABLE=$(terraform -chdir=infra/terraform output -raw dynamodb_table_name)
TAG=${1:-dev}
helm upgrade --install $APP charts/todo-api   --namespace $NS --create-namespace   --set image.repository=$ECR_URL   --set image.tag=$TAG   --set env.TABLE_NAME=$TABLE   --set service.type=LoadBalancer   --set ingress.enabled=false
