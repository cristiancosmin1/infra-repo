.PHONY: infra bootstrap verify down

infra:
	@echo "Infrastructure is managed from cloud-repo/terraform"

bootstrap:
	./bootstrap/bootstrap.sh

verify:
	./bootstrap/05-verify.sh

down:
	cd ../cloud-repo/terraform && terraform destroy
