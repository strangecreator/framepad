#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
developer_dir="$(xcode-select -p)"
if [ "$developer_dir" = /Library/Developer/CommandLineTools ]; then
    swift test --scratch-path .build-tests --disable-sandbox --disable-xctest --enable-swift-testing \
        -Xswiftc -F -Xswiftc "$developer_dir/Library/Developer/Frameworks" \
        -Xlinker -rpath -Xlinker "$developer_dir/Library/Developer/Frameworks" \
        -Xlinker -rpath -Xlinker "$developer_dir/Library/Developer/usr/lib"
else
    swift test --disable-sandbox
fi
