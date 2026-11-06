#!/usr/bin/env bash
# Invoked only by `sudo unshare --net`; never changes host networking.
set -euo pipefail
test "$#" -eq 1
test "$(id -u)" -eq 0
test -n "${REPORT_NETWORK_HOST_NAMESPACE:?}"
test "$(readlink /proc/self/ns/net)" != "$REPORT_NETWORK_HOST_NAMESPACE"
test "$(ip -o link show | wc -l)" -eq 1
ip link show lo >/dev/null
test -z "$(ip -4 route show table main)"
test -z "$(ip -6 route show table main)"

# Flutter's host/tester protocol needs loopback. There is no external interface
# or default route; the local table will consequently contain loopback routes.
ip link set lo up
readlink /proc/self/ns/net > "$REPORT_NETWORK_QA_OUTPUT/isolated-namespace.txt"
ip -j address show > "$REPORT_NETWORK_QA_OUTPUT/isolated-addresses.json"
ip -j -4 route show table all > "$REPORT_NETWORK_QA_OUTPUT/isolated-ipv4-all-routes.json"
ip -j -6 route show table all > "$REPORT_NETWORK_QA_OUTPUT/isolated-ipv6-all-routes.json"

# Drop back to the original runner user. Dependencies and native hooks were
# prepared outside this namespace, and --no-pub prevents dependency resolution.
exec runuser -u "$1" -- env \
  "PATH=$PATH" \
  "FLUTTER_ROOT=$FLUTTER_ROOT" \
  "PUB_CACHE=$PUB_CACHE" \
  "REPORT_NETWORK_HOST_NAMESPACE=$REPORT_NETWORK_HOST_NAMESPACE" \
  "REPORT_NETWORK_QA_OUTPUT=$REPORT_NETWORK_QA_OUTPUT" \
  "REPORT_NETWORK_QA_COMMIT=$REPORT_NETWORK_QA_COMMIT" \
  REPORT_NETWORK_QA_PHASE=isolated \
  CI=true FLUTTER_SUPPRESS_ANALYTICS=true OTZARIA_REQUIRE_SEARCH_ENGINE=1 \
  flutter test --no-pub --concurrency=1 --reporter expanded \
  --file-reporter "json:$REPORT_NETWORK_QA_OUTPUT/test-results.json" \
  test/reports/network_isolation_qa_test.dart
