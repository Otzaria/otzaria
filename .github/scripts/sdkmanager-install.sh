#!/usr/bin/env bash
# sdkmanager --install <package...> with retries. A large package (system image,
# NDK) sometimes arrives truncated ("Error reading Zip content"); a new download succeeds.
set -uo pipefail
sdkmanager="${ANDROID_SDK_ROOT:-$ANDROID_HOME}/cmdline-tools/latest/bin/sdkmanager"
for attempt in 1 2 3; do
  "$sdkmanager" --install "$@" && exit 0
  echo "::warning::sdkmanager --install $* failed (attempt $attempt/3)"
  [ "$attempt" = 3 ] || sleep $((attempt * 15))
done
exit 1
