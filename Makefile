.PHONY: deploy-frontend deploy-backend build-all

AWS_REGION ?= eu-central-1
AWS_ACCOUNT_ID ?= $(shell aws sts get-caller-identity --query Account --output text)
ECR_REPO ?= spry-backend
S3_BUCKET ?= spry-frontend-app

deploy-frontend:
	@echo "==> Building frontend..."
	cd frontend && npm install && npm run build
	@echo "==> Deploying to S3..."
	aws s3 sync frontend/dist/ s3://$(S3_BUCKET) --delete

deploy-backend:
	@echo "==> Building and pushing backend Docker image..."
	aws ecr get-login-password --region $(AWS_REGION) | docker login --username AWS --password-stdin $(AWS_ACCOUNT_ID).dkr.ecr.$(AWS_REGION).amazonaws.com
	docker build -t $(ECR_REPO):latest ./backend
	docker tag $(ECR_REPO):latest $(AWS_ACCOUNT_ID).dkr.ecr.$(AWS_REGION).amazonaws.com/$(ECR_REPO):latest
	docker push $(AWS_ACCOUNT_ID).dkr.ecr.$(AWS_REGION).amazonaws.com/$(ECR_REPO):latest
