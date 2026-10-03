#!/usr/bin/env bash
set -euo pipefail

task_app_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd -- "$task_app_dir"

if [[ ! -f config/firebase_options.json ]]; then
  printf '%s\n' \
    'Missing config/firebase_options.json.' \
    'Copy config/firebase_options.example.json to that path and fill in your Firebase app configuration.' >&2
  exit 1
fi

exec flutter run --dart-define-from-file=config/firebase_options.json "$@"
