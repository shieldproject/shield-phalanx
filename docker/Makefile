.DEFAULT_GOAL := help
COMPOSE := docker compose -f docker-compose.yml

SHIELD_REPO     ?= https://github.com/shieldproject/shield.git
SHIELD_BRANCH   ?= develop
SHIELD_SRC      := ../src/shield
UBUNTU_RELEASE  ?= noble
GO_VERSION      ?= 1.26.1
export UBUNTU_RELEASE GO_VERSION SHIELD_BRANCH

.PHONY: help build up down test logs clean status shell fetch-shield

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-15s\033[0m %s\n", $$1, $$2}'

fetch-shield: ## Clone or update SHIELD source (branch: SHIELD_BRANCH)
	@if [ -d "$(SHIELD_SRC)/.git" ]; then \
		echo "Updating SHIELD source (branch: $(SHIELD_BRANCH))..."; \
		cd $(SHIELD_SRC) && git fetch origin && git checkout $(SHIELD_BRANCH) && git pull origin $(SHIELD_BRANCH); \
	else \
		echo "Cloning SHIELD source (branch: $(SHIELD_BRANCH))..."; \
		git clone -b $(SHIELD_BRANCH) $(SHIELD_REPO) $(SHIELD_SRC); \
	fi

build: fetch-shield ## Build all Docker images
	$(COMPOSE) build

up: ## Start all services (detached)
	$(COMPOSE) up -d

down: ## Stop all services
	$(COMPOSE) down

test: build ## Run the full test suite (build, up, run tests, down)
	$(COMPOSE) up -d core agent postgres mariadb mongodb consul etcd cert-init etcd-tls rustfs
	$(COMPOSE) run --rm tests; rc=$$?; $(COMPOSE) down; exit $$rc

logs: ## Tail all service logs
	$(COMPOSE) logs -f

clean: ## Remove all containers, volumes, and images
	$(COMPOSE) down -v --rmi local

status: ## Show service health status
	$(COMPOSE) ps

shell: ## Open a debug shell in the tests container
	$(COMPOSE) run --rm --entrypoint /bin/bash tests
