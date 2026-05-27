.DEFAULT_GOAL := help
SHELL := bash

.PHONY: help install lint fmt test clean

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-9s\033[0m %s\n",$$1,$$2}'

install: ## Install the pre-commit git hooks
	pre-commit install

lint: ## Run every linter/formatter (pre-commit) across the repo
	pre-commit run --all-files

fmt: ## Format shell scripts (shfmt, via pre-commit)
	-pre-commit run shfmt --all-files

test: ## Run the bats test suite
	bats --print-output-on-failure tests/

clean: ## Remove local run artifacts (worktrees, tasks/)
	rm -rf .worktrees tasks
