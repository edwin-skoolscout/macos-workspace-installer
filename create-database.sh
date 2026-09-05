#!/usr/bin/env bash
# create-database.sh — local Postgres instances, one data dir each (tools/create-database).
#
#   ./create-database.sh create              # instance named after the current directory
#   ./create-database.sh create mydb --port 5440 --user app --password secret
#   ./create-database.sh status mydb         # data dir, version, port, running?
#   ./create-database.sh stop mydb
#   ./create-database.sh list
#
# Instances live in DATABASES_DIR/<name> (config/versions.env), the layout of
# jefelabs-scripts/tools/setup-database.sh, which this tool replaces.
set -euo pipefail
# shellcheck source=lib/node-tool.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/node-tool.sh"
run_node_tool create-database "$@"
