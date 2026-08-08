#!/usr/bin/env bash
#
# Builds a debug APK you can install on your own phone.
#
# No signing to set up: debug builds are signed with Android's standard debug key,
# which every phone accepts. This is the one to use for testing.
#
#   ./build-debug.sh              build it
#   ./build-debug.sh --install    build and push it over USB
#
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

# shellcheck source=build.conf
[ -f build.conf ] && . ./build.conf

./build-apk.sh "$@"

cat <<TXT

    Next: copy ${APP_SLUG:-app}-debug.apk to the phone and tap it.
    Allow your file manager to install unknown apps when asked.

    (No developer mode needed. On Xiaomi, "Install via USB" is
     more trouble than it's worth - just copy the file across.)
TXT
