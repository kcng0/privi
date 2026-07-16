# Convenience wrapper. Uses `fvm flutter` if FVM is set up, else plain `flutter`.
FLUTTER := $(shell command -v fvm >/dev/null 2>&1 && echo "fvm flutter" || echo "flutter")

.PHONY: help bootstrap get gen watch format analyze test run apk clean

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
	  awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-12s\033[0m %s\n", $$1, $$2}'

bootstrap: ## One-time project setup (native scaffold + deps + codegen)
	./scripts/bootstrap.sh

get: ## Fetch dependencies
	$(FLUTTER) pub get

gen: ## Run code generation once (drift + riverpod)
	$(FLUTTER) pub run build_runner build --delete-conflicting-outputs

watch: ## Run code generation in watch mode
	$(FLUTTER) pub run build_runner watch --delete-conflicting-outputs

format: ## Format all Dart code
	dart format lib test

analyze: ## Static analysis
	$(FLUTTER) analyze

test: ## Run tests
	$(FLUTTER) test

run: ## Run on a connected device
	$(FLUTTER) run

apk: ## Build a release APK (sideload)
	$(FLUTTER) build apk --release

clean: ## Clean build artifacts
	$(FLUTTER) clean
