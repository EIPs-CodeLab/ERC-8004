# Environment Variables
include .env
export $(shell sed 's/=.*//' .env)

# Phony targets
.PHONY: all build test clean deploy-sepolia update-deps help

help: ## Show this help
	@echo "Usage: make [target]"
	@echo ""
	@echo "Targets:"
	@grep -E '^[a-zA-Z0-9_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'

all: build test ## Build and test

build: ## Build contracts
	forge build

test: ## Run tests
	forge test

clean: ## Clean build artifacts
	forge clean

deploy-sepolia: ## Deploy contracts to Sepolia
	@echo "Deploying to Sepolia..."
	forge script script/Deploy.s.sol:DeployERC8004 --rpc-url $(SEPOLIA_RPC_URL) --broadcast --verify -vvvv

deploy-local: ## Deploy contracts to local Anvil node
	@echo "Deploying to Local Anvil..."
	forge script script/Deploy.s.sol:DeployERC8004 --rpc-url http://127.0.0.1:8545 --broadcast --private-key 0x2a871d0798f97d79848a013d4936a73bf4cc922c825d33c1cf7073dff6d409c6 -vvvv

update-deps: ## Update Foundry dependencies
	forge update

format: ## Format code
	forge fmt
