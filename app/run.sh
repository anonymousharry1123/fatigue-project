#!/usr/bin/env bash
set -euo pipefail

task_app_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd -- "$task_app_dir"

if [[ ! -f lib/src/firebase_secrets.dart ]]; then
  printf '%s\n' \
    'Missing lib/src/firebase_secrets.dart.' \
    'Create it once without overwriting an existing configuration:' \
    '  cp -n lib/src/firebase_secrets.example.dart lib/src/firebase_secrets.dart' \
    'Leave the constants empty for offline mode, or fill them with your Firebase app configuration and rebuild.' >&2
  exit 1
fi

exec flutter run "$@"
