COMPOSE := docker compose

.PHONY: help up down reset lint test deploy-backend deploy-frontend domain github-role destroy-backend destroy-frontend destroy-github-role logs-backend

help: ## Show targets
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-22s %s\n", $$1, $$2}'

up: ## Build and start postgres, the API, and the Vite app
	$(COMPOSE) up --build

down: ## Stop the stack
	$(COMPOSE) down

reset: ## Stop the stack and delete the database volume
	$(COMPOSE) down -v

lint: ## Run ruff, eslint, prettier, and tsc inside the images
	$(COMPOSE) build backend frontend
	$(COMPOSE) run --rm --no-deps --user root --entrypoint sh backend -c "pip install -q -r requirements-dev.txt && ruff check . && ruff format --check ."
	$(COMPOSE) run --rm --no-deps --entrypoint sh frontend -c "npm run lint && npm run format:check && npx tsc --noEmit"

test: ## Run pytest against spry_test, and the frontend unit tests
	$(COMPOSE) build backend frontend
	$(COMPOSE) run --rm --user root --entrypoint sh -e DATABASE_URL=postgresql+psycopg://postgres:postgres@postgres:5432/spry_test backend -c "pip install -q -r requirements-dev.txt && pytest"
	$(COMPOSE) run --rm --no-deps --entrypoint npm frontend test

deploy-backend: ## Build the image, push it to ECR, roll the ECS service
	./scripts/deploy-backend.sh

deploy-frontend: ## Build the bundle, sync it to S3, invalidate CloudFront
	./scripts/deploy-frontend.sh

domain: ## Certificate plus app/api DNS for a domain you own
	./scripts/domain.sh

github-role: ## Create the OIDC role GitHub Actions assumes
	./scripts/github-role.sh

destroy-backend: ## Delete the API, load balancer, and database
	./scripts/destroy-backend.sh

destroy-frontend: ## Delete the bucket and the CloudFront distribution
	./scripts/destroy-frontend.sh

destroy-github-role: ## Delete the deploy role
	./scripts/destroy-github-role.sh

logs-backend: ## Tail the deployed API logs
	aws logs tail /ecs/$${PROJECT_NAME:-spry}-backend --follow --since 10m
