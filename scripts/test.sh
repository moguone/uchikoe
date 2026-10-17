#!/bin/bash
# 単体テストを動かす
set -euo pipefail
cd "$(dirname "$0")/.."
swift test
