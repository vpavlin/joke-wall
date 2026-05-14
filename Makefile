# joke-wall — SPEL Program
#
# Quick start:
#   make build idl deploy setup
#   make cli ARGS="<command> --arg1 value1"

SHELL := /bin/bash
STATE_FILE := .joke_wall-state
IDL_FILE := joke-wall-idl.json
PROGRAMS_DIR := methods/guest/target/riscv32im-risc0-zkvm-elf/docker
PROGRAM_BIN := $(PROGRAMS_DIR)/joke_wall.bin

-include $(STATE_FILE)

define save_var
	@grep -v '^$(1)=' $(STATE_FILE) 2>/dev/null > $(STATE_FILE).tmp || true
	@echo '$(1)=$(2)' >> $(STATE_FILE).tmp
	@mv $(STATE_FILE).tmp $(STATE_FILE)
endef

.PHONY: help build idl cli deploy setup inspect status clean

help: ## Show this help
	@echo "joke-wall — SPEL Program"
	@echo ""
	@echo "  make build       Build the guest binary (needs risc0 toolchain)"
	@echo "  make idl         Generate IDL from program source"
	@echo "  make cli ARGS=   Run the IDL-driven CLI (reads spel.toml for config)"
	@echo "  make deploy      Deploy program to sequencer"
	@echo "  make setup       Create accounts needed for the program"
	@echo "  make inspect     Show ProgramId for built binary"
	@echo "  make status      Show saved state and binary info"
	@echo "  make clean       Remove saved state"
	@echo ""
	@echo "Workflow:"
	@echo "  make build idl deploy"
	@echo "  make setup"
	@echo "  make cli ARGS=\"create_session --description 'Best Jokes 2026'\""
	@echo "  make cli ARGS=\"submit_joke --content 'Why do programmers prefer dark mode?'\""
	@echo "  make cli ARGS=\"vote --joke_index 0\""
	@echo "  make cli ARGS=\"close_session\""

build: ## Build the guest binary
	cargo risczero build --manifest-path methods/guest/Cargo.toml
	@echo ""
	@echo "✅ Guest binary built: $(PROGRAM_BIN)"
	@ls -la $(PROGRAM_BIN) 2>/dev/null || true

idl: ## Generate IDL JSON from guest source
	spel generate-idl methods/guest/src/bin/joke_wall.rs > $(IDL_FILE)
	@echo "✅ IDL written to $(IDL_FILE)"

cli: ## Run the IDL-driven CLI (ARGS="...")
	cargo run --bin joke_wall_cli -- $(ARGS)

deploy: ## Deploy program to sequencer
	@test -f "$(PROGRAM_BIN)" || (echo "ERROR: Binary not found. Run 'make build' first."; exit 1)
	wallet deploy-program $(PROGRAM_BIN)
	@echo "✅ Program deployed"

inspect: ## Show ProgramId for built binary
	cargo run --bin joke_wall_cli -- inspect $(PROGRAM_BIN)

setup: ## Create admin and voter accounts
	@echo "Creating admin account..."
	$(eval ADMIN_ID := $(shell wallet account new public 2>&1 | sed -n 's/.*Public\/\([A-Za-z0-9]*\).*/\1/p'))
	@echo "Admin: Public/$(ADMIN_ID)"
	$(call save_var,ADMIN_ID,$(ADMIN_ID))
	@echo ""
	@echo "Creating voter account..."
	$(eval VOTER_ID := $(shell wallet account new public 2>&1 | sed -n 's/.*Public\/\([A-Za-z0-9]*\).*/\1/p'))
	@echo "Voter: Public/$(VOTER_ID)"
	$(call save_var,VOTER_ID,$(VOTER_ID))
	@echo ""
	@echo "✅ Accounts saved to $(STATE_FILE)"

status: ## Show saved state and binary info
	@echo "joke-wall Status"
	@echo "──────────────────────────────────────"
	@if [ -f "$(STATE_FILE)" ]; then cat $(STATE_FILE); else echo "(no state — run 'make setup')"; fi
	@echo ""
	@echo "Binaries:"
	@ls -la $(PROGRAM_BIN) 2>/dev/null || echo "  joke_wall.bin: NOT BUILT (run 'make build')"
	@echo ""
	@echo "IDL:"
	@ls -la $(IDL_FILE) 2>/dev/null || echo "  $(IDL_FILE): NOT GENERATED (run 'make idl')"

clean: ## Remove saved state
	rm -f $(STATE_FILE) $(STATE_FILE).tmp
	@echo "✅ State cleaned"
