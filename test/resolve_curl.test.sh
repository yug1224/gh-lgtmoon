#!/usr/bin/env bash

ROOT=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=../gh-lgtmoon
source "$ROOT/gh-lgtmoon"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

FAKE=$(mktemp -d)
trap 'rm -rf "$FAKE"' EXIT

NOT_FOUND_MSG='gh-lgtmoon: curl not found'

make_fake() {
  local name=$1
  local body=$2
  printf '%s\n' "$body" >"$FAKE/$name"
  chmod +x "$FAKE/$name"
}

make_fake_runnable() {
  make_fake "$1" '#!/bin/bash
printf "%s\n" "curl fake" >&2
exit 0'
}

make_fake_broken() {
  make_fake "$1" '#!/bin/bash
printf "%s\n" "dyld: Library not loaded" >&2
exit 134'
}

assert_file_bytes_eq() {
  local name=$1
  local file=$2
  local want=$3

  cmp -s "$file" <(printf '%s' "$want") || fail "$name: byte mismatch for $file"
}

assert_file_empty() {
  local name=$1
  local file=$2

  if [ -s "$file" ]; then
    fail "$name: expected empty file, got '$(cat "$file")'"
  fi
}

assert_stdout_eq() {
  local name=$1
  local got=$2
  local want=$3

  if [ "$got" != "$want" ]; then
    fail "$name: expected '$want', got '$got'"
  fi
}

# 1. system path returns a runnable fake → resolve_curl prints that path
rm -f "$FAKE"/*
make_fake_runnable system_curl
make_fake_runnable path_curl
out=$(mktemp)
err=$(mktemp)
(
  system_curl_path() { printf '%s\n' "$FAKE/system_curl"; }
  path_curl_path() { printf '%s\n' "$FAKE/path_curl"; }
  resolve_curl >"$out" 2>"$err"
) || fail 'case 1: resolve_curl returned non-zero'
assert_stdout_eq 'case 1: stdout' "$(cat "$out")" "$FAKE/system_curl"
assert_file_empty 'case 1: stderr' "$err"
rm -f "$out" "$err"

# 2. system path empty; path_curl_path returns runnable fake → that fake
rm -f "$FAKE"/*
make_fake_runnable path_curl
out=$(mktemp)
err=$(mktemp)
(
  system_curl_path() { :; }
  path_curl_path() { printf '%s\n' "$FAKE/path_curl"; }
  resolve_curl >"$out" 2>"$err"
) || fail 'case 2: resolve_curl returned non-zero'
assert_stdout_eq 'case 2: stdout' "$(cat "$out")" "$FAKE/path_curl"
assert_file_empty 'case 2: stderr' "$err"
rm -f "$out" "$err"

# 3. system path returns failing fake; path_curl_path returns runnable fake → PATH fake
rm -f "$FAKE"/*
make_fake_broken system_curl
make_fake_runnable path_curl
out=$(mktemp)
err=$(mktemp)
(
  system_curl_path() { printf '%s\n' "$FAKE/system_curl"; }
  path_curl_path() { printf '%s\n' "$FAKE/path_curl"; }
  resolve_curl >"$out" 2>"$err"
) || fail 'case 3: resolve_curl returned non-zero'
assert_stdout_eq 'case 3: stdout' "$(cat "$out")" "$FAKE/path_curl"
assert_file_empty 'case 3: stderr' "$err"
rm -f "$out" "$err"

# 4. system path returns failing fake; path_curl_path returns failing fake → fail + stderr
rm -f "$FAKE"/*
make_fake_broken system_curl
make_fake_broken path_curl
out=$(mktemp)
err=$(mktemp)
(
  system_curl_path() { printf '%s\n' "$FAKE/system_curl"; }
  path_curl_path() { printf '%s\n' "$FAKE/path_curl"; }
  resolve_curl >"$out" 2>"$err"
) && fail 'case 4: resolve_curl should return 1'
assert_file_empty 'case 4: stdout' "$out"
assert_file_bytes_eq 'case 4: stderr' "$err" "${NOT_FOUND_MSG}"$'\n'
rm -f "$out" "$err"

# 5. both empty → same fail + stderr
rm -f "$FAKE"/*
out=$(mktemp)
err=$(mktemp)
(
  system_curl_path() { :; }
  path_curl_path() { :; }
  resolve_curl >"$out" 2>"$err"
) && fail 'case 5: resolve_curl should return 1'
assert_file_empty 'case 5: stdout' "$out"
assert_file_bytes_eq 'case 5: stderr' "$err" "${NOT_FOUND_MSG}"$'\n'
rm -f "$out" "$err"

# 6. integration: PATH fake curl must not win over /usr/bin/curl
if [ -x /usr/bin/curl ]; then
  rm -f "$FAKE"/*
  make_fake_runnable curl
  out=$(mktemp)
  err=$(mktemp)
  (
    export PATH="$FAKE"
    resolve_curl >"$out" 2>"$err"
  ) || fail 'case 6: resolve_curl returned non-zero'
  assert_stdout_eq 'case 6: stdout' "$(cat "$out")" /usr/bin/curl
  assert_file_empty 'case 6: stderr' "$err"
  rm -f "$out" "$err"
fi

printf 'OK: resolve_curl tests passed\n'
