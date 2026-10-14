#!/bin/zsh
# Прогон тестов логики (без Xcode, только Command Line Tools)
set -e
cd "$(dirname "$0")"
mkdir -p build
swiftc -swift-version 5 -O Sources/Core/*.swift Tests/*.swift -o build/tests
./build/tests
