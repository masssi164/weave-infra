.PHONY: dev-hosts smoke release-verify operator-check

DEV_HOSTS_LINE := 127.0.0.1 weave.local auth.weave.local files.weave.local matrix.weave.local

dev-hosts:
	@printf '%s\n' 'Add this line to /etc/hosts for the default local stack:'
	@printf '%s\n' '$(DEV_HOSTS_LINE)'

smoke:
	@bash weave-workspace/smoke-test.sh

release-verify:
	@bash weave-workspace/release-verify.sh

operator-check:
	@bash weave-workspace/operator-check.sh
