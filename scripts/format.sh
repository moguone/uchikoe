#!/bin/bash
# swift format でソースを整形する
set -euo pipefail
cd "$(dirname "$0")/.."
swift format --in-place --recursive --configuration .swift-format Package.swift Sources Tests
