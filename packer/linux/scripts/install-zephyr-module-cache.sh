#!/bin/bash
set -eu -o pipefail

echo "install west"
sudo pip3 install west

echo "install module cache"
# Create a copy of the zephyr modules
mkdir -p zephyr-module-cache/.z
cd zephyr-module-cache/.z
wget https://raw.githubusercontent.com/zephyrproject-rtos/zephyr/master/west.yml
/usr/local/bin/west init -l .
/usr/local/bin/west update

# Clean things up
# 1. Remove everything that isn't under a .git dir
# 2. remove temp .z dir
# 3. remove .west dir
cd /home/ec2-user/zephyr-module-cache
find -type f -not -path "*/.git/*" -not -name ".git" -delete
rmdir .z
rmdir .west

cd /home/ec2-user
sudo chown -R buildkite-agent.docker zephyr-module-cache
sudo mv zephyr-module-cache /var/lib/buildkite-agent/

df -h
