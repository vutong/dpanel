#!/usr/bin/env bash
set -euo pipefail

hostname -I 2>/dev/null | awk '{print $1}'
