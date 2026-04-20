.PHONY: dev-hosts smoke

DEV_HOSTS_LINE := 127.0.0.1 keycloak.weave.local nextcloud.weave.local matrix.weave.local mas.weave.local api.weave.local

dev-hosts:
	@printf '%s\n' 'Add this line to /etc/hosts for the default local stack:'
	@printf '%s\n' '$(DEV_HOSTS_LINE)'

smoke:
	@bash weave-workspace/smoke-test.sh
