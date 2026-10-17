#!/bin/bash
# swift format の決まりに沿っているかを確かめる。直すときは scripts/format.sh
set -euo pipefail
cd "$(dirname "$0")/.."
swift format lint --strict --recursive --configuration .swift-format Package.swift Sources Tests
