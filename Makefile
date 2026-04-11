APP_PROD := app_name
APP_TEST := app_name_test

PLUGIN_ROOT ?= $(shell pwd)

deploy:
	./tools/deploy/deploy.sh $(APP_PROD)

deploy-test:
	./tools/deploy/deploy.sh $(APP_TEST)

# Install plugin hooks into the consumer repo's .claude/settings.json.
# Run from the consumer repo: make -f /path/to/claude-plugin/Makefile install-plugin PLUGIN_ROOT=/path/to/claude-plugin
# Or copy this target into the consumer repo's Makefile and set PLUGIN_ROOT.
install-plugin:
	@mkdir -p .claude
	@[ -f .claude/settings.json ] || echo '{}' > .claude/settings.json
	@jq -s --arg root "$(PLUGIN_ROOT)" \
	  '.[0] * .[1] * {env: {CLAUDE_PLUGIN_ROOT: $$root}}' \
	  .claude/settings.json "$(PLUGIN_ROOT)/hooks/hooks.json" \
	  > .claude/settings.tmp && mv .claude/settings.tmp .claude/settings.json
	@echo "Plugin hooks installed. CLAUDE_PLUGIN_ROOT=$(PLUGIN_ROOT)"
