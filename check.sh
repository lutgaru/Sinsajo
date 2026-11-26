#!/usr/bin/env bash
# Run the same checks as CI locally.
#
# Usage:
#   ./check.sh                 # check the Rust server and the Flutter client
#   ./check.sh --server        # only the Rust server
#   ./check.sh --client        # only the Flutter client
#   ./check.sh --build         # also build release artifacts
#   ./check.sh --help
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT"

SERVER_DIR="$ROOT/server"
CLIENT_DIR="$ROOT/sinsajo_client"

run_server=0
run_client=0
run_build=0

usage() {
  cat <<'EOF'
Usage: ./check.sh [options]

Options:
  --server    Check only the Rust server (server/)
  --client    Check only the Flutter client (sinsajo_client/)
  --build     Also run release builds (cargo build --release, flutter build web --release)
  -h, --help  Show this help

With no project flags, both projects are checked.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --server) run_server=1 ;;
    --client) run_client=1 ;;
    --build) run_build=1 ;;
    -h|--help) usage; exit 0 ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

if [[ $run_server -eq 0 && $run_client -eq 0 ]]; then
  run_server=1
  run_client=1
fi

step() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
ok()   { printf '\033[1;32m✓ %s\033[0m\n' "$*"; }
fail() { printf '\033[1;31m✗ %s\033[0m\n' "$*" >&2; }

step "Shell scripts"
bash -n "$ROOT/check.sh" "$ROOT/setup-hooks.sh" "$ROOT/.githooks/pre-commit" "$ROOT/.githooks/pre-push"
ok "Shell syntax"

find_flutter() {
  if [[ -n "${FLUTTER_BIN:-}" && -x "${FLUTTER_BIN}" ]]; then
    printf '%s\n' "$FLUTTER_BIN"
    return 0
  fi

  if command -v flutter >/dev/null 2>&1; then
    command -v flutter
    return 0
  fi

  local candidate
  for candidate in \
    "$HOME/flutter/flutter/bin/flutter" \
    "$HOME/development/flutter/bin/flutter" \
    "$HOME/Flutter/flutter/bin/flutter" \
    "/opt/flutter/bin/flutter" \
    "/usr/local/flutter/bin/flutter"; do
    if [[ -x "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  return 1
}

find_dart() {
  if command -v dart >/dev/null 2>&1; then
    command -v dart
    return 0
  fi

  local flutter_bin
  flutter_bin="$(find_flutter)" || return 1

  local candidate
  candidate="$(dirname "$flutter_bin")/dart"
  if [[ -x "$candidate" ]]; then
    printf '%s\n' "$candidate"
    return 0
  fi

  return 1
}

if [[ $run_server -eq 1 ]]; then
  step "Rust server"
  if ! command -v cargo >/dev/null 2>&1; then
    fail "cargo not found in PATH"
    exit 1
  fi
  if [[ ! -f "$SERVER_DIR/Cargo.toml" ]]; then
    fail "server/Cargo.toml not found"
    exit 1
  fi

  step "cargo fmt --check"
  (cd "$SERVER_DIR" && cargo fmt --all -- --check)
  ok "Rust formatting"

  step "cargo check"
  (cd "$SERVER_DIR" && cargo check --quiet --workspace --all-targets)
  ok "cargo check"

  step "cargo clippy"
  (cd "$SERVER_DIR" && cargo clippy --quiet --workspace --all-targets --all-features -- -D warnings -W clippy::all)
  ok "cargo clippy"

  step "cargo test"
  (cd "$SERVER_DIR" && cargo test --quiet --workspace --all-targets)
  ok "cargo test"

  if [[ $run_build -eq 1 ]]; then
    step "cargo build --release"
    (cd "$SERVER_DIR" && cargo build --release)
    ok "cargo build --release"
  fi
fi

if [[ $run_client -eq 1 ]]; then
  step "Flutter client"
  if [[ ! -f "$CLIENT_DIR/pubspec.yaml" ]]; then
    fail "sinsajo_client/pubspec.yaml not found"
    exit 1
  fi

  if ! FLUTTER="$(find_flutter)"; then
    fail "Flutter not found. Add it to PATH or set FLUTTER_BIN=/path/to/flutter."
    exit 1
  fi
  if ! DART="$(find_dart)"; then
    fail "dart not found. Add Flutter's bin directory to PATH or set FLUTTER_BIN."
    exit 1
  fi

  step "dart format --check"
  (cd "$CLIENT_DIR" && "$DART" format --output=none --set-exit-if-changed lib test)
  ok "Dart formatting"

  step "flutter analyze"
  (cd "$CLIENT_DIR" && "$FLUTTER" analyze)
  ok "flutter analyze"

  step "flutter test"
  (cd "$CLIENT_DIR" && "$FLUTTER" test)
  ok "flutter test"

  if [[ $run_build -eq 1 ]]; then
    step "flutter build web --release"
    (cd "$CLIENT_DIR" && "$FLUTTER" build web --release)
    ok "flutter build web --release"
  fi
fi

printf '\n\033[1;32m✅ All checks passed.\033[0m\n'
