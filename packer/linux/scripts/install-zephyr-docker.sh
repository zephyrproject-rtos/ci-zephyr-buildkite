#!/bin/bash
set -eu -o pipefail

DOCKER_ZEPHYR_CI_TAG=v0.11.8

# Since EnableDockerUserNamespaceRemap is true we need to mimic
# the setting of userns-remap when we pull the docker image
cat <<< "$(jq '."userns-remap"="buildkite-agent"' /etc/docker/daemon.json)" > /etc/docker/daemon.json

sudo systemctl start docker.service
sudo docker pull zephyrprojectrtos/ci:${DOCKER_ZEPHYR_CI_TAG}
sudo systemctl stop docker.service

cat <<< "$(jq 'del(."userns-remap")' /etc/docker/daemon.json)" > /etc/docker/daemon.json
