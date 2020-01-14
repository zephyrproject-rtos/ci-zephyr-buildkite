#!/bin/bash
set -eu -o pipefail

sudo git clone -v --mirror -- https://github.com/zephyrproject-rtos/zephyr /var/lib/buildkite-agent/git-mirrors/https---github-com-zephyrproject-rtos-zephyr
sudo chown -R buildkite-agent.buildkite-agent /var/lib/buildkite-agent/git-mirrors/https---github-com-zephyrproject-rtos-zephyr
