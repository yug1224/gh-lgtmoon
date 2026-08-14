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

MD='![LGTM](https://example.com/x)'
SKIP_MSG='gh-lgtmoon: clipboard copy skipped'

read_proc_version() { :; }

make_fake() {
  local name=$1
  local body=$2
  printf '%s\n' "$body" >"$FAKE/$name"
  chmod +x "$FAKE/$name"
}

make_fake_success() {
  make_fake "$1" '#!/bin/bash
while IFS= read -r line || [ -n "$line" ]; do
  printf "%s\n" "$line"
done >"'"$FAKE/$1.out"'"
printf "%s" "$*" >"'"$FAKE/$1.args"'"
exit 0'
}

make_fake_fail() {
  make_fake "$1" '#!/bin/bash
while IFS= read -r line || [ -n "$line" ]; do
  printf "%s\n" "$line"
done >"'"$FAKE/$1.out"'"
printf "%s" "$*" >"'"$FAKE/$1.args"'"
exit 1'
}

assert_file_bytes_eq() {
  local name=$1
  local file=$2
  local want=$3

  cmp -s "$file" <(printf '%s' "$want") || fail "$name: byte mismatch for $file"
}

assert_file_eq() {
  local name=$1
  local file=$2
  local want=$3
  local got

  got=$(cat "$file")
  if [ "$got" != "$want" ]; then
    fail "$name: expected '$want', got '$got'"
  fi
}

assert_file_empty() {
  local name=$1
  local file=$2

  if [ -s "$file" ]; then
    fail "$name: expected empty file, got '$(cat "$file")'"
  fi
}

assert_no_file() {
  local name=$1
  local file=$2

  if [ -e "$file" ]; then
    fail "$name: expected no file at $file"
  fi
}

assert_args_contain() {
  local name=$1
  local file=$2
  local needle=$3
  local args

  args=$(cat "$file")
  case "$args" in
    *"$needle"*) ;;
    *) fail "$name: expected args to contain '$needle', got '$args'" ;;
  esac
}

# 1. fake pbcopy only → success
rm -f "$FAKE"/*
make_fake_success pbcopy
out=$(mktemp)
err=$(mktemp)
(
  export PATH="$FAKE"
  unset DISPLAY WAYLAND_DISPLAY
  OSTYPE=linux-gnu
  clipboard_copy "$MD"
) || fail 'case 1: clipboard_copy returned non-zero'
assert_file_bytes_eq 'case 1: pbcopy.out' "$FAKE/pbcopy.out" "${MD}"$'\n'
(
  export PATH="$FAKE"
  unset DISPLAY WAYLAND_DISPLAY
  OSTYPE=linux-gnu
  print_and_copy "$MD" >"$out" 2>"$err"
) || fail 'case 1: print_and_copy returned non-zero'
assert_file_empty 'case 1: stderr' "$err"
rm -f "$out" "$err"

# 2. fake pbcopy exits 1
rm -f "$FAKE"/*
make_fake_fail pbcopy
(
  export PATH="$FAKE"
  unset DISPLAY WAYLAND_DISPLAY
  OSTYPE=linux-gnu
  clipboard_copy "$MD"
) && fail 'case 2: clipboard_copy should return 1'
out=$(mktemp)
err=$(mktemp)
(
  export PATH="$FAKE"
  unset DISPLAY WAYLAND_DISPLAY
  OSTYPE=linux-gnu
  print_and_copy "$MD" >"$out" 2>"$err"
) || fail 'case 2: print_and_copy returned non-zero'
assert_file_bytes_eq 'case 2: stdout' "$out" "${MD}"$'\n'
assert_file_bytes_eq 'case 2: stderr' "$err" "${SKIP_MSG}"$'\n'
rm -f "$out" "$err"

# 3. no tools → skip
rm -f "$FAKE"/*
(
  export PATH="$FAKE"
  unset DISPLAY WAYLAND_DISPLAY
  OSTYPE=linux-gnu
  clipboard_copy "$MD"
) && fail 'case 3: clipboard_copy should return 1'
out=$(mktemp)
err=$(mktemp)
(
  export PATH="$FAKE"
  unset DISPLAY WAYLAND_DISPLAY
  OSTYPE=linux-gnu
  print_and_copy "$MD" >"$out" 2>"$err"
) || fail 'case 3: print_and_copy returned non-zero'
assert_file_bytes_eq 'case 3: stdout' "$out" "${MD}"$'\n'
assert_file_bytes_eq 'case 3: stderr' "$err" "${SKIP_MSG}"$'\n'
rm -f "$out" "$err"

# 4. pbcopy AND xclip AND clip.exe all present → only pbcopy.out
rm -f "$FAKE"/*
make_fake_success pbcopy
make_fake_success xclip
make_fake_success clip.exe
(
  export PATH="$FAKE"
  unset DISPLAY WAYLAND_DISPLAY
  OSTYPE=linux-gnu
  clipboard_copy "$MD"
) || fail 'case 4: clipboard_copy returned non-zero'
assert_no_file 'case 4: xclip.out' "$FAKE/xclip.out"
assert_no_file 'case 4: clip.exe.out' "$FAKE/clip.exe.out"
assert_file_bytes_eq 'case 4: pbcopy.out' "$FAKE/pbcopy.out" "${MD}"$'\n'

# 5. OSTYPE=msys, clip.exe and xclip (DISPLAY=:0) → only clip.exe.out
rm -f "$FAKE"/*
make_fake_success clip.exe
make_fake_success xclip
(
  export PATH="$FAKE"
  export DISPLAY=:0
  unset WAYLAND_DISPLAY
  OSTYPE=msys
  clipboard_copy "$MD"
) || fail 'case 5: clipboard_copy returned non-zero'
assert_no_file 'case 5: xclip.out' "$FAKE/xclip.out"
assert_file_bytes_eq 'case 5: clip.exe.out' "$FAKE/clip.exe.out" "${MD}"$'\n'

# 6. OSTYPE=linux-gnu, read_proc_version prints Microsoft, clip.exe and xclip → clip.exe wins
rm -f "$FAKE"/*
make_fake_success clip.exe
make_fake_success xclip
(
  export PATH="$FAKE"
  export DISPLAY=:0
  unset WAYLAND_DISPLAY
  OSTYPE=linux-gnu
  read_proc_version() { printf '%s' 'Microsoft WSL'; }
  clipboard_copy "$MD"
) || fail 'case 6: clipboard_copy returned non-zero'
assert_no_file 'case 6: xclip.out' "$FAKE/xclip.out"
assert_file_bytes_eq 'case 6: clip.exe.out' "$FAKE/clip.exe.out" "${MD}"$'\n'

# 7. OSTYPE=linux-gnu, read_proc_version empty, clip.exe and xclip, DISPLAY=:0 → xclip wins
rm -f "$FAKE"/*
make_fake_success clip.exe
make_fake_success xclip
(
  export PATH="$FAKE"
  export DISPLAY=:0
  unset WAYLAND_DISPLAY
  OSTYPE=linux-gnu
  read_proc_version() { :; }
  clipboard_copy "$MD"
) || fail 'case 7: clipboard_copy returned non-zero'
assert_no_file 'case 7: clip.exe.out' "$FAKE/clip.exe.out"
assert_file_bytes_eq 'case 7: xclip.out' "$FAKE/xclip.out" "${MD}"$'\n'

# 8. WAYLAND_DISPLAY=wayland-0, fake wl-copy, DISPLAY=:0 and fake xclip → only wl-copy
rm -f "$FAKE"/*
make_fake_success wl-copy
make_fake_success xclip
(
  export PATH="$FAKE"
  export WAYLAND_DISPLAY=wayland-0
  export DISPLAY=:0
  OSTYPE=linux-gnu
  clipboard_copy "$MD"
) || fail 'case 8: clipboard_copy returned non-zero'
assert_no_file 'case 8: xclip.out' "$FAKE/xclip.out"
assert_file_bytes_eq 'case 8: wl-copy.out' "$FAKE/wl-copy.out" "${MD}"$'\n'

# 9. wl-copy present but WAYLAND_DISPLAY unset, DISPLAY=:0 and xclip → xclip
rm -f "$FAKE"/*
make_fake_success wl-copy
make_fake_success xclip
(
  export PATH="$FAKE"
  unset WAYLAND_DISPLAY
  export DISPLAY=:0
  OSTYPE=linux-gnu
  clipboard_copy "$MD"
) || fail 'case 9: clipboard_copy returned non-zero'
assert_no_file 'case 9: wl-copy.out' "$FAKE/wl-copy.out"
assert_file_bytes_eq 'case 9: xclip.out' "$FAKE/xclip.out" "${MD}"$'\n'

# 10. DISPLAY=:0, fake xclip → success, args contain -selection clipboard
rm -f "$FAKE"/*
make_fake_success xclip
(
  export PATH="$FAKE"
  export DISPLAY=:0
  unset WAYLAND_DISPLAY
  OSTYPE=linux-gnu
  clipboard_copy "$MD"
) || fail 'case 10: clipboard_copy returned non-zero'
assert_file_bytes_eq 'case 10: xclip.out' "$FAKE/xclip.out" "${MD}"$'\n'
assert_args_contain 'case 10: xclip args' "$FAKE/xclip.args" '-selection clipboard'

# 11. DISPLAY=:0, no xclip, fake xsel → success, args contain --clipboard --input
rm -f "$FAKE"/*
make_fake_success xsel
(
  export PATH="$FAKE"
  export DISPLAY=:0
  unset WAYLAND_DISPLAY
  OSTYPE=linux-gnu
  clipboard_copy "$MD"
) || fail 'case 11: clipboard_copy returned non-zero'
assert_file_bytes_eq 'case 11: xsel.out' "$FAKE/xsel.out" "${MD}"$'\n'
assert_args_contain 'case 11: xsel args' "$FAKE/xsel.args" '--clipboard --input'

# 12. xclip/xsel present but DISPLAY unset → skip
rm -f "$FAKE"/*
make_fake_success xclip
make_fake_success xsel
(
  export PATH="$FAKE"
  unset DISPLAY WAYLAND_DISPLAY
  OSTYPE=linux-gnu
  clipboard_copy "$MD"
) && fail 'case 12: clipboard_copy should return 1'
out=$(mktemp)
err=$(mktemp)
(
  export PATH="$FAKE"
  unset DISPLAY WAYLAND_DISPLAY
  OSTYPE=linux-gnu
  print_and_copy "$MD" >"$out" 2>"$err"
) || fail 'case 12: print_and_copy returned non-zero'
assert_file_bytes_eq 'case 12: stdout' "$out" "${MD}"$'\n'
assert_file_bytes_eq 'case 12: stderr' "$err" "${SKIP_MSG}"$'\n'
rm -f "$out" "$err"

# 13. print_and_copy success → stdout bytes equal MD + one NL, stderr empty
rm -f "$FAKE"/*
make_fake_success pbcopy
out=$(mktemp)
err=$(mktemp)
(
  export PATH="$FAKE"
  unset DISPLAY WAYLAND_DISPLAY
  OSTYPE=linux-gnu
  print_and_copy "$MD" >"$out" 2>"$err"
) || fail 'case 13: print_and_copy returned non-zero'
cmp -s "$out" <(printf '%s\n' "$MD") || fail 'case 13: stdout bytes mismatch'
assert_file_empty 'case 13: stderr' "$err"
rm -f "$out" "$err"

# 14. print_and_copy skip → stdout same as 13, stderr skip message
rm -f "$FAKE"/*
out=$(mktemp)
err=$(mktemp)
(
  export PATH="$FAKE"
  unset DISPLAY WAYLAND_DISPLAY
  OSTYPE=linux-gnu
  print_and_copy "$MD" >"$out" 2>"$err"
) || fail 'case 14: print_and_copy returned non-zero'
cmp -s "$out" <(printf '%s\n' "$MD") || fail 'case 14: stdout bytes mismatch'
assert_file_bytes_eq 'case 14: stderr' "$err" "${SKIP_MSG}"$'\n'
rm -f "$out" "$err"

# 15. pbcopy=fail, xclip=success → xclip wins
rm -f "$FAKE"/*
make_fake_fail pbcopy
make_fake_success xclip
(
  export PATH="$FAKE"
  export DISPLAY=:0
  unset WAYLAND_DISPLAY
  OSTYPE=linux-gnu
  read_proc_version() { :; }
  clipboard_copy "$MD"
) || fail 'case 15: clipboard_copy returned non-zero'
assert_file_bytes_eq 'case 15: xclip.out' "$FAKE/xclip.out" "${MD}"$'\n'
out=$(mktemp)
err=$(mktemp)
(
  export PATH="$FAKE"
  export DISPLAY=:0
  unset WAYLAND_DISPLAY
  OSTYPE=linux-gnu
  read_proc_version() { :; }
  print_and_copy "$MD" >"$out" 2>"$err"
) || fail 'case 15: print_and_copy returned non-zero'
assert_file_empty 'case 15: stderr' "$err"
rm -f "$out" "$err"

# 16. WSL, clip.exe=fail, xclip=success → xclip wins, clip.exe attempted
rm -f "$FAKE"/*
make_fake_fail clip.exe
make_fake_success xclip
(
  export PATH="$FAKE"
  export DISPLAY=:0
  unset WAYLAND_DISPLAY
  OSTYPE=linux-gnu
  read_proc_version() { printf '%s' 'Microsoft WSL'; }
  clipboard_copy "$MD"
) || fail 'case 16: clipboard_copy returned non-zero'
assert_file_bytes_eq 'case 16: clip.exe.out' "$FAKE/clip.exe.out" "${MD}"$'\n'
assert_file_bytes_eq 'case 16: xclip.out' "$FAKE/xclip.out" "${MD}"$'\n'

# 17. xclip=fail, xsel=success → xsel wins
rm -f "$FAKE"/*
make_fake_fail xclip
make_fake_success xsel
(
  export PATH="$FAKE"
  export DISPLAY=:0
  unset WAYLAND_DISPLAY
  OSTYPE=linux-gnu
  clipboard_copy "$MD"
) || fail 'case 17: clipboard_copy returned non-zero'
assert_file_bytes_eq 'case 17: xsel.out' "$FAKE/xsel.out" "${MD}"$'\n'
assert_args_contain 'case 17: xsel args' "$FAKE/xsel.args" '--clipboard --input'

# 18. wl-copy=fail, xclip=success → xclip wins, wl-copy attempted
rm -f "$FAKE"/*
make_fake_fail wl-copy
make_fake_success xclip
(
  export PATH="$FAKE"
  export WAYLAND_DISPLAY=wayland-0
  export DISPLAY=:0
  OSTYPE=linux-gnu
  clipboard_copy "$MD"
) || fail 'case 18: clipboard_copy returned non-zero'
assert_file_bytes_eq 'case 18: wl-copy.out' "$FAKE/wl-copy.out" "${MD}"$'\n'
assert_file_bytes_eq 'case 18: xclip.out' "$FAKE/xclip.out" "${MD}"$'\n'

# 19. WSL, all fail → clipboard_copy returns 1, print_and_copy skips
rm -f "$FAKE"/*
make_fake_fail clip.exe
make_fake_fail xclip
make_fake_fail xsel
(
  export PATH="$FAKE"
  export DISPLAY=:0
  unset WAYLAND_DISPLAY
  OSTYPE=linux-gnu
  read_proc_version() { printf '%s' 'Microsoft WSL'; }
  clipboard_copy "$MD"
) && fail 'case 19: clipboard_copy should return 1'
out=$(mktemp)
err=$(mktemp)
(
  export PATH="$FAKE"
  export DISPLAY=:0
  unset WAYLAND_DISPLAY
  OSTYPE=linux-gnu
  read_proc_version() { printf '%s' 'Microsoft WSL'; }
  print_and_copy "$MD" >"$out" 2>"$err"
) || fail 'case 19: print_and_copy returned non-zero'
assert_file_bytes_eq 'case 19: stdout' "$out" "${MD}"$'\n'
assert_file_bytes_eq 'case 19: stderr' "$err" "${SKIP_MSG}"$'\n'
rm -f "$out" "$err"

printf 'All tests passed.\n'
