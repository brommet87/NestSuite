# NestSuite developer tasks. Run `make help` for an overview.
.DEFAULT_GOAL := help
SCHEME        := NestSuite
DERIVED       := build/DerivedData
PACKAGE       := Packages/NestKit

.PHONY: help bootstrap generate build test test-package test-app lint format icon run clean

help: ## Show available tasks
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}'

bootstrap: ## Install developer tools (Homebrew required)
	brew bundle --file=Brewfile

generate: ## Generate NestSuite.xcodeproj from project.yml
	xcodegen generate --quiet

build: generate ## Build the app (Debug, ad-hoc signed)
	xcodebuild -project NestSuite.xcodeproj -scheme $(SCHEME) -configuration Debug \
		-derivedDataPath $(DERIVED) build -quiet

test: test-package test-app ## Run all tests

test-package: ## Run NestKit unit tests (fast, no VM required)
	swift test --package-path $(PACKAGE) --parallel

test-app: generate ## Run app-level tests via xcodebuild
	xcodebuild -project NestSuite.xcodeproj -scheme $(SCHEME) -derivedDataPath $(DERIVED) test -quiet

lint: ## Lint and check formatting
	swiftlint --strict --quiet
	swiftformat --lint . --quiet

format: ## Auto-format all Swift sources
	swiftformat . --quiet

icon: ## Re-render the app icon from code
	Scripts/render-app-icon.sh

run: build ## Build and launch the app
	open $(DERIVED)/Build/Products/Debug/NestSuite.app

clean: ## Remove build products
	rm -rf build NestSuite.xcodeproj $(PACKAGE)/.build
