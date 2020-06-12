.PHONY: all clean build packer upload

VERSION = $(shell git describe --tags --candidates=1)
SHELL = /bin/bash -o pipefail

PACKER_LINUX_FILES = $(exec find packer/linux)
PACKER_WINDOWS_FILES = $(exec find packer/windows)

AWS_REGION ?= us-east-1
AMZN_LINUX2_AMI ?= $(shell aws ec2 describe-images --region $(AWS_REGION) --owners amazon --filters 'Name=name,Values=amzn2-ami-hvm-2.0.????????-x86_64-gp2' 'Name=state,Values=available' --output json | jq -r '.Images | sort_by(.CreationDate) | last(.[]).ImageId')

ARCH ?= x86_64
ifeq ($(ARCH), arm64)
  INSTANCE_TYPE = m6g.xlarge
else
  INSTANCE_TYPE = c5.xlarge
endif

all: packer build

# Remove any built cloudformation templates and packer output
clean:
	-rm -rf build/*
	-rm packer*.output

# Check for specific environment variables
env-%:
	@ if [ "${${*}}" = "" ]; then \
		echo "Environment variable $* not set"; \
		exit 1; \
	fi

# -----------------------------------------

build: packer build/aws-stack.yml

# Build a mapping file for a single region and image id pair
mappings-for-linux-image: env-AWS_REGION env-IMAGE_ID
	mkdir -p build/
	printf "Mappings:\n  AWSRegion2AMI:\n    %s: { linux: %s, windows: '' }\n" \
		"$(AWS_REGION)" $(IMAGE_ID) > build/mappings.yml

# Build a windows mapping file for a single region and image id pair
mappings-for-windows-image: env-AWS_REGION env-IMAGE_ID
	mkdir -p build/
	printf "Mappings:\n  AWSRegion2AMI:\n    %s: { linux: '', windows: %s }\n" \
		"$(AWS_REGION)" $(IMAGE_ID) > build/mappings.yml

# Takes the mappings files and copies them into a generated stack template
.PHONY: build/aws-stack.yml
build/aws-stack.yml:
	test -f build/mappings.yml
	awk '{ \
		if ($$0 ~ /AWSRegion2AMI:/ && system("test -f build/mappings.yml") == 0) { \
			system("grep -v Mappings: build/mappings.yml") \
		} else { \
			print \
		}\
	}' templates/aws-stack.yml | sed "s/%v/$(VERSION)/" > $@

# -----------------------------------------
# AMI creation with Packer

packer: packer-linux.output

build/mappings.yml: build/linux-ami.txt
	mkdir -p build
	printf "Mappings:\n  AWSRegion2AMI:\n    %q : { linux: %q }\n" \
		"$(AWS_REGION)" $$(cat build/linux-ami.txt) > $@

build/linux-ami.txt: packer-linux.output env-AWS_REGION
	mkdir -p build
	grep -Eo "$(AWS_REGION): (ami-.+)" $< | cut -d' ' -f2 | xargs echo -n > $@

# Build linux packer image
packer-linux.output: $(PACKER_LINUX_FILES) env-STACK_NAME
	docker run \
		-e AWS_DEFAULT_REGION  \
		-e AWS_PROFILE \
		-e AWS_ACCESS_KEY_ID \
		-e AWS_SECRET_ACCESS_KEY \
		-e AWS_SESSION_TOKEN \
		-e PACKER_LOG \
		-v ${HOME}/.aws:/root/.aws \
		-v "$(PWD):/src" \
		--rm \
		-w /src/packer/linux \
		hashicorp/packer:1.0.4 build -var 'ami=$(AMZN_LINUX2_AMI)' -var 'region=$(AWS_REGION)' \
			-var 'arch=$(ARCH)' -var 'instance_type=$(INSTANCE_TYPE)' \
			-var 'stack_name=$(STACK_NAME)' \
			buildkite-ami.json | tee $@

build/windows-ami.txt: packer-windows.output env-AWS_REGION
	mkdir -p build
	grep -Eo "$(AWS_REGION): (ami-.+)" $< | cut -d' ' -f2 | xargs echo -n > $@

# Build windows packer image
packer-windows.output: $(PACKER_WINDOWS_FILES)
	docker run \
		-e AWS_DEFAULT_REGION  \
		-e AWS_PROFILE \
		-e AWS_ACCESS_KEY_ID \
		-e AWS_SECRET_ACCESS_KEY \
		-e AWS_SESSION_TOKEN \
		-e PACKER_LOG \
		-v ${HOME}/.aws:/root/.aws \
		-v "$(PWD):/src" \
		--rm \
		-w /src/packer/windows \
		hashicorp/packer:1.0.4 build -var 'region=$(AWS_REGION)' \
			buildkite-ami.json | tee $@

# -----------------------------------------
# Cloudformation helpers

TEMPLATE = aws-stack.yml

config.json:
	cp config.json.example config.json

create-stack: build/aws-stack.yml env-STACK_NAME
	aws cloudformation create-stack \
		--output text \
		--stack-name $(STACK_NAME) \
		--disable-rollback \
		--template-body "file://$(PWD)/build/aws-stack.yml" \
		--capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
		--parameters "$$(cat config.json)"

update-stack: build/aws-stack.yml env-STACK_NAME
	aws cloudformation update-stack \
		--output text \
		--stack-name $(STACK_NAME) \
		--template-body "file://$(PWD)/build/aws-stack.yml" \
		--capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
		--parameters "$$(cat config.json)"


# -----------------------------------------
# Other

AGENT_VERSION ?= $(shell curl -Lfs "https://buildkite.com/agent/releases/latest?platform=linux&arch=amd64" | grep version | cut -d= -f2)

bump-agent-version:
	sed -i.bak -E "s/\[Buildkite Agent v.*\]/[Buildkite Agent v$(AGENT_VERSION)]/g" README.md
	sed -i.bak -E "s/AGENT_VERSION=.+/AGENT_VERSION=$(AGENT_VERSION)/g" packer/linux/scripts/install-buildkite-agent.sh
	sed -i.bak -E "s/\\\$$AGENT_VERSION = \".+\"/\$$AGENT_VERSION = \"$(AGENT_VERSION)\"/g" packer/windows/scripts/install-buildkite-agent.ps1
	rm README.md.bak packer/linux/scripts/install-buildkite-agent.sh.bak packer/windows/scripts/install-buildkite-agent.ps1.bak
	git add README.md packer/linux/scripts/install-buildkite-agent.sh packer/windows/scripts/install-buildkite-agent.ps1
	git commit -m "Bump buildkite-agent to v$(AGENT_VERSION)"

validate: build/aws-stack.yml
	aws cloudformation validate-template \
		--output text \
		--template-body "file://$(PWD)/build/aws-stack.yml"

generate-toc:
	docker run -it --rm -v "$(PWD):/app" node:slim bash \
		-c "npm install -g markdown-toc && cd /app && markdown-toc -i README.md"
