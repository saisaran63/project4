#!/usr/bin/env bash
set -euo pipefail
ECR_URL=$(terraform -chdir=infra/terraform output -raw ecr_repository_url)
IMAGE_TAG=${1:-dev}
aws ecr get-login-password | docker login --username AWS --password-stdin ${ECR_URL}
docker build -t ${ECR_URL}:${IMAGE_TAG} ./app
docker push ${ECR_URL}:${IMAGE_TAG}
