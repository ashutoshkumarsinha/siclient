# SICLient — IMS SIP Client for macOS Tahoe
#
# Common targets:
#   make              — build CLI + GUI (default)
#   make test         — run all 122 tests
#   make dry-run      — bootstrap smoke (no signaling)
#   make acceptance   — full acceptance suite
#   make help         — list all targets

SWIFT       ?= swift
PROFILE     ?= profiles/lab-volte-01.json
MO_DEST     ?= sip:001010987654321@ims.mnc001.mcc001.3gppnetwork.org
BUILD_DIR   := .build/debug
CLI         := $(BUILD_DIR)/siclient
GUI         := $(BUILD_DIR)/siclient-gui

.PHONY: all build build-cli build-gui test test-core test-gui test-filter \
        run run-gui dry-run register deregister mo-call acceptance gui-smoke \
        clean help docs

# Default: build everything
all: build

## Build -----------------------------------------------------------------------

build: build-cli build-gui ## Build CLI and GUI executables

build-cli: ## Build siclient CLI only
	$(SWIFT) build --product siclient

build-gui: ## Build siclient-gui SwiftUI app only
	$(SWIFT) build --product siclient-gui

## Test ------------------------------------------------------------------------

test: build ## Run all unit + integration tests (122)
	$(SWIFT) test

test-core: build-cli ## Run SICLientCoreTests only (107)
	$(SWIFT) test --filter SICLientCoreTests

test-gui: build ## Run SICLientGUITests only (15)
	$(SWIFT) test --filter SICLientGUITests

test-filter: build ## Run tests matching FILTER= (e.g. make test-filter FILTER=Registration)
	@test -n "$(FILTER)" || (echo "Usage: make test-filter FILTER=RegistrationTests" && exit 1)
	$(SWIFT) test --filter "$(FILTER)"

## Run -------------------------------------------------------------------------

run: build-cli register ## Register against profile (alias)

dry-run: build-cli ## Load profile and bootstrap without signaling
	$(SWIFT) run siclient --profile $(PROFILE) --dry-run

register: build-cli ## Register against P-CSCF in profile
	$(SWIFT) run siclient --profile $(PROFILE)

deregister: build-cli ## Register then send Expires: 0
	$(SWIFT) run siclient --profile $(PROFILE) --deregister

mo-call: build-cli ## MO VoLTE call (MO_DEST=, CALL_DURATION=, HOLD=1, DTMF=)
	$(SWIFT) run siclient --profile $(PROFILE) \
		--mo-call $(MO_DEST) \
		--call-duration $(or $(CALL_DURATION),2) \
		$(if $(HOLD),--hold,) \
		$(if $(DTMF),--dtmf $(DTMF),)

run-gui: build-gui ## Launch SwiftUI lab console
	$(SWIFT) run siclient-gui

## Acceptance ------------------------------------------------------------------

acceptance: build ## Full acceptance suite (tests + CLI + GUI + optional SIPp)
	chmod +x Tests/sipp/run-acceptance.sh Tests/gui/run-gui-smoke.sh
	./Tests/sipp/run-acceptance.sh

gui-smoke: build ## GUI build verification + ViewModel tests
	chmod +x Tests/gui/run-gui-smoke.sh
	./Tests/gui/run-gui-smoke.sh

## Clean -----------------------------------------------------------------------

clean: ## Remove build artifacts
	$(SWIFT) package clean
	rm -rf .build

## Help ------------------------------------------------------------------------

docs: ## List documentation paths
	@echo "docs/user-guide.md         — CLI/GUI user guide"
	@echo "docs/deployment-guide.md   — build, install, configure"
	@echo "docs/integration-guide.md  — developer integration"
	@echo "docs/operator-interop-runbook.md — IMS lab validation"
	@echo "docs/api-reference.md      — public API"
	@echo "docs/ARCHITECTURE.md       — module map"
	@echo "spec.md                    — functional specification"

help: ## Show this help
	@echo "SICLient Makefile"
	@echo ""
	@echo "Variables:"
	@echo "  PROFILE=$(PROFILE)"
	@echo "  MO_DEST=$(MO_DEST)"
	@echo "  FILTER=     (for test-filter)"
	@echo "  CALL_DURATION=  HOLD=1  DTMF=<digit>  (for mo-call)"
	@echo ""
	@grep -E '^[a-zA-Z0-9_-]+:.*##' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*## "}; {printf "  %-16s %s\n", $$1, $$2}'
