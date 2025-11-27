# AWS DevOps Real-Time Project: Cloud-Native ToDo API

A production-style AWS DevOps project that provisions cloud infra with Terraform, ships a Dockerized FastAPI service via CI/CD (GitHub Actions) to Amazon EKS, stores data in DynamoDB, and includes monitoring/logging, blue/green deployments via Helm, and automated tests.

## Architecture (High-Level)
- **IaC**: Terraform provisions VPC, EKS, ECR, IAM roles, DynamoDB, and supporting resources.
- **App**: Python FastAPI microservice (`/app`) providing CRUD ToDo endpoints.
- **Container**: Docker builds and pushes images to **Amazon ECR**.
- **Cluster**: **Amazon EKS** with a **Helm chart** for deployment (+ HPA, liveness/readiness probes).
- **Ingress**: AWS Load Balancer Controller exposes app via an ALB.
- **Data**: **DynamoDB** table for todos (PAY_PER_REQUEST mode).
- **CI/CD**: GitHub Actions: test → build → push → deploy (manual approve to prod).
- **Observability**: CloudWatch logs, Prometheus scraping annotations, basic alerts example.
- **Security**: Least-privileged IAM roles for service account (IRSA), image scanning, branch protections (docs).

---

## Prerequisites
- An AWS account and **AdministratorAccess** (for initial setup only).
- Locally installed: `awscli v2`, `kubectl`, `helm`, `terraform >= 1.6`, `docker`.
- A GitHub repo with the code pushed.
- Domain is optional. If you have one in Route53, set `enable_ingress=true` and configure DNS later.

## 1) Bootstrap: AWS & Terraform
1. Configure AWS credentials locally:
   ```bash
   aws configure
   ```
2. Create an S3 bucket and DynamoDB table for Terraform state (edit names):
   ```bash
   aws s3 mb s3://my-tf-state-<uniq>
   aws dynamodb create-table      --table-name tf-locks      --attribute-definitions AttributeName=LockID,AttributeType=S      --key-schema AttributeName=LockID,KeyType=HASH      --billing-mode PAY_PER_REQUEST
   ```
3. In `infra/terraform/backend.hcl`, set your bucket/table names. Then:
   ```bash
   cd infra/terraform
   terraform init -backend-config=backend.hcl
   terraform apply -auto-approve
   ```
   Output will include: VPC id, EKS cluster name, ECR repo URL, DynamoDB table name, etc.

4. Update your local kubeconfig:
   ```bash
   aws eks update-kubeconfig --name $(terraform output -raw eks_cluster_name) --region $(terraform output -raw aws_region)
   ```

## 2) Install AWS Load Balancer Controller (once per cluster)
```bash
kubectl apply -k "github.com/aws/eks-charts/stable/aws-load-balancer-controller//crds?ref=master"
helm repo add eks https://aws.github.io/eks-charts
helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller   -n kube-system   --set clusterName=$(terraform -chdir=infra/terraform output -raw eks_cluster_name)   --set serviceAccount.create=false   --set serviceAccount.name=aws-load-balancer-controller   --set region=$(terraform -chdir=infra/terraform output -raw aws_region)   --set vpcId=$(terraform -chdir=infra/terraform output -raw vpc_id)
```
> Terraform creates the IRSA role and service account for the controller; see `modules/eks/irsa.tf`.

## 3) Local run (optional)
```bash
python -m venv .venv && source .venv/bin/activate
pip install -r app/requirements.txt
export TABLE_NAME=$(terraform -chdir=infra/terraform output -raw dynamodb_table_name)
uvicorn app.main:app --reload --port 8000
```

## 4) Build & push image
```bash
export ECR=$(terraform -chdir=infra/terraform output -raw ecr_repository_url)
aws ecr get-login-password | docker login --username AWS --password-stdin ${ECR}
docker build -t todo-api:local ./app
docker tag todo-api:local ${ECR}:local
docker push ${ECR}:local
```

## 5) Helm deploy (dev)
```bash
helm upgrade --install todo-api charts/todo-api   --namespace todo --create-namespace   --set image.repository=$(terraform -chdir=infra/terraform output -raw ecr_repository_url)   --set image.tag=local   --set env.TABLE_NAME=$(terraform -chdir=infra/terraform output -raw dynamodb_table_name)   --set service.type=LoadBalancer   --set ingress.enabled=false
```
> Get the external address: `kubectl get svc -n todo`

## 6) CI/CD via GitHub Actions
- Create repository **Secrets** in GitHub:
  - `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_REGION`
  - `ECR_REPOSITORY` (from Terraform output)
  - `EKS_CLUSTER_NAME` (from Terraform output)
  - `DDB_TABLE_NAME` (from Terraform output)
- Push this repo; Actions will run:
  - **ci.yml**: lint & tests on PRs.
  - **deploy.yml**: on push to `main`, build → push image → helm upgrade.

Manual promotion to prod is included with an `environment: production` protection (requires approval).

## 7) Observability
- **Logs**: container `stdout/stderr` → CloudWatch via EKS node settings.
- **Metrics**: annotations allow Prometheus scraping.
- **Alerts**: sample CloudWatch alarm JSON in `observability/alarms`.

## 8) Cleanup
```bash
terraform -chdir=infra/terraform destroy
```

> ⚠️ Costs: EKS, ALB, and nodes cost money. Use small node groups and tear down when done.

---

### Project structure
```
app/               # FastAPI microservice
charts/            # Helm chart for the service
infra/terraform/   # Terraform IaC (VPC, EKS, ECR, DynamoDB, IAM/IRSA)
.github/workflows/ # CI/CD pipelines
observability/     # sample dashboards/alarms
scripts/           # helper scripts
```

