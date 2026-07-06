# meshvpn — Makefile. Pure shell tool: no compile step.
.DEFAULT_GOAL := help
SH ?= bash

.PHONY: help test lint demo install clean docker check

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
	  awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-10s\033[0m %s\n", $$1, $$2}'

test: ## Run the self-contained test suite
	$(SH) tests/run.sh

lint: ## Static-analyse all shell with shellcheck
	shellcheck -x meshvpn.sh lib/*.sh tests/run.sh

check: lint test ## Lint + test

demo: ## Run the end-to-end demo
	$(SH) examples/demo.sh

install: ## Install meshvpn onto your PATH
	$(SH) install.sh

docker: ## Build the container image
	docker build -t meshvpn:latest .

clean: ## Remove generated output dirs
	rm -rf out ./*/wg*.conf
