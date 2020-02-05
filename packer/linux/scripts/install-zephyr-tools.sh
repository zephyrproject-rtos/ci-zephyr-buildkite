#!/bin/bash
set -eu -o pipefail

echo "install makeself (used by sdk-ng package)"
MAKESELF_VERSION=2.4.2
wget -q https://github.com/megastep/makeself/releases/download/release-${MAKESELF_VERSION}/makeself-${MAKESELF_VERSION}.run
chmod a+x makeself-${MAKESELF_VERSION}.run
./makeself-${MAKESELF_VERSION}.run
sudo cp ./makeself-${MAKESELF_VERSION}/makeself.sh /usr/local/bin/makeself
rm -fr ./makeself-${MAKESELF_VERSION}*

# tree used by sdk-ng
sudo yum install -y tree
