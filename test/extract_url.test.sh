#!/usr/bin/env bash

ROOT=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=../gh-lgtmoon
source "$ROOT/gh-lgtmoon"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

assert_extract_eq() {
  local name=$1
  local json=$2
  local want=$3
  local got

  got=$(printf '%s' "$json" | extract_lgtm_url) || fail "$name: extract_lgtm_url returned non-zero"
  if [ "$got" != "$want" ]; then
    fail "$name: expected '$want', got '$got'"
  fi
}

assert_extract_fail() {
  local name=$1
  local json=$2

  if printf '%s' "$json" | extract_lgtm_url >/dev/null 2>&1; then
    fail "$name: expected extract_lgtm_url to fail"
  fi
}

assert_validate_ok() {
  local name=$1
  local url=$2

  validate_https_url "$url" || fail "$name: expected validate_https_url to accept '$url'"
}

assert_validate_fail() {
  local name=$1
  local url=$2

  if validate_https_url "$url"; then
    fail "$name: expected validate_https_url to reject '$url'"
  fi
}

assert_extract_eq 'success' \
  '{"images":[{"url":"https://example.com/lgtm.png","isConverted":true}]}' \
  'https://example.com/lgtm.png'

assert_extract_fail 'empty images' '{"images":[]}'

assert_extract_fail 'not json' 'not json'

assert_extract_eq 'multiple urls' \
  '{"images":[{"url":"https://image.lgtmoon.dev/first.png","isConverted":true},{"url":"https://image.lgtmoon.dev/second.png","isConverted":false}]}' \
  'https://image.lgtmoon.dev/first.png'

assert_validate_ok 'https lgtmoon' 'https://image.lgtmoon.dev/123'
assert_validate_fail 'http scheme' 'http://example.com/x'
assert_validate_fail 'empty url' ''
assert_validate_fail 'whitespace in url' 'https://example.com/x y'
assert_validate_fail 'javascript scheme' 'javascript:alert(1)'

printf 'All tests passed.\n'
