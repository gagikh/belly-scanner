#!/usr/bin/env bash
#
# Shared helpers for build-apk.sh / build-debug.sh / build-release.sh.
# Sourced, never run directly.

# ---------------------------------------------------------------- settings ---
# Order of precedence: environment variable > build.local.conf > build.conf > default.
# build.local.conf is gitignored — put machine-specific paths there.
load_build_conf() {
  local dir="$1"
  local keep_id="${APP_ID:-}"     keep_name="${APP_NAME:-}"  keep_slug="${APP_SLUG:-}"
  local keep_sdk="${TARGET_SDK:-}" keep_ks="${KEYSTORE_FILE:-}" keep_alias="${KEY_ALIAS:-}"
  local keep_dname="${KEY_DNAME:-}" keep_kt="${KEYTOOL:-}"   keep_jh="${JAVA_HOME:-}"

  # shellcheck source=build.conf
  [ -f "$dir/build.conf" ]       && . "$dir/build.conf"
  # shellcheck disable=SC1091
  [ -f "$dir/build.local.conf" ] && . "$dir/build.local.conf"

  [ -n "$keep_id" ]    && APP_ID="$keep_id"
  [ -n "$keep_name" ]  && APP_NAME="$keep_name"
  [ -n "$keep_slug" ]  && APP_SLUG="$keep_slug"
  [ -n "$keep_sdk" ]   && TARGET_SDK="$keep_sdk"
  [ -n "$keep_ks" ]    && KEYSTORE_FILE="$keep_ks"
  [ -n "$keep_alias" ] && KEY_ALIAS="$keep_alias"
  [ -n "$keep_dname" ] && KEY_DNAME="$keep_dname"
  [ -n "$keep_kt" ]    && KEYTOOL="$keep_kt"
  [ -n "$keep_jh" ]    && JAVA_HOME="$keep_jh"

  APP_ID="${APP_ID:-com.example.app}"
  APP_NAME="${APP_NAME:-App}"
  APP_SLUG="${APP_SLUG:-app}"
  TARGET_SDK="${TARGET_SDK:-36}"
  return 0
}

# ------------------------------------------------------------------- paths ---
WINHOST=0
case "$(uname -s 2>/dev/null || echo unknown)" in
  MINGW*|MSYS*|CYGWIN*) WINHOST=1 ;;
esac

# set when a JDK was found but rejected as the wrong version, so callers can explain
JAVA_REJECTED=""

# POSIX path -> native (C:/style), which Gradle accepts and .properties files need
native_path() {
  if [ "$WINHOST" = "1" ] && command -v cygpath >/dev/null 2>&1; then
    cygpath -m "$1" 2>/dev/null || printf '%s' "$1"
  else
    printf '%s' "$1"
  fi
}

# native path -> POSIX, so the shell can test and cd into it
posix_path() {
  if [ "$WINHOST" = "1" ] && command -v cygpath >/dev/null 2>&1; then
    cygpath -u "$1" 2>/dev/null || printf '%s' "$1"
  else
    printf '%s' "$1"
  fi
}

# Every drive letter that actually exists, as POSIX roots: /c /d /t ...
# Android Studio is routinely installed somewhere other than C:.
win_drives() {
  local d
  for d in a b c d e f g h i j k l m n o p q r s t u v w x y z; do
    [ -d "/$d" ] && printf '%s\n' "/$d"
  done
}

# ------------------------------------------------------------- jdk discovery ---
# Gradle refuses to run on a JDK newer than it understands, with the memorable
# "Unsupported class file major version NN" (69 = Java 25, 68 = 24, 67 = 23,
# 66 = 22, 65 = 21, 61 = 17). Android tooling is happy on 17 or 21, so we pick a
# JDK in that window rather than whatever happens to be first on PATH.
JAVA_MIN="${JAVA_MIN:-17}"
JAVA_MAX="${JAVA_MAX:-21}"

# Major version of the JDK at $1, or nothing if it won't run
java_major() {
  local out v
  out="$("$1/bin/java" -version 2>&1 | head -n1)" || return 1
  v="$(printf '%s' "$out" | sed -n 's/.*version "\([0-9][0-9.]*\).*/\1/p')"
  [ -n "$v" ] || return 1
  case "$v" in
    1.*) printf '%s' "$(printf '%s' "$v" | cut -d. -f2)" ;;   # 1.8 -> 8
    *)   printf '%s' "$(printf '%s' "$v" | cut -d. -f1)" ;;
  esac
}

# Finds a JDK that Gradle can actually use, and sets:
#   JAVA_FOUND    - the JDK home (POSIX form), on success
#   JAVA_REJECTED - a JDK we had to skip, for the error message
# Sets globals rather than echoing, because $( ) runs in a subshell and the
# explanation of *why* nothing was found would be thrown away with it.
# JAVA_HOME is preferred, but only if its version is in range: silently building
# on an unusable JDK just produces a baffling error later.
detect_java() {
  local cand jh drive best="" best_v=0 v
  local -a candidates=()
  JAVA_FOUND=""
  JAVA_REJECTED=""

  jh="$(posix_path "${JAVA_HOME:-}")"
  if [ -n "$jh" ] && [ -d "$jh/bin" ]; then
    v="$(java_major "$jh" 2>/dev/null || true)"
    if [ -n "$v" ] && [ "$v" -ge "$JAVA_MIN" ] && [ "$v" -le "$JAVA_MAX" ]; then
      JAVA_FOUND="$jh"; return 0
    fi
    JAVA_REJECTED="$jh (Java ${v:-?})"
  fi

  # Android Studio's bundled JDK, wherever the app happens to live.
  # An array, not a space-joined string: every one of these paths contains
  # "Program Files" or "Android Studio", so word-splitting would shred them.
  local -a bases=()
  [ -n "${ANDROID_STUDIO_HOME:-}" ] && bases+=("$(posix_path "$ANDROID_STUDIO_HOME")")
  [ -n "${ProgramFiles:-}" ]        && bases+=("$(posix_path "$ProgramFiles")/Android/Android Studio")
  [ -n "${LOCALAPPDATA:-}" ]        && bases+=("$(posix_path "$LOCALAPPDATA")/Programs/Android Studio")
  bases+=("$HOME/android-studio" "/opt/android-studio" "/usr/local/android-studio")
  bases+=("/Applications/Android Studio.app/Contents")

  if [ "$WINHOST" = "1" ]; then
    while IFS= read -r drive; do
      [ -n "$drive" ] || continue
      bases+=("$drive/Program Files/Android/Android Studio")
      bases+=("$drive/Program Files (x86)/Android/Android Studio")
      bases+=("$drive/Android/Android Studio")
    done <<< "$(win_drives)"
  fi

  local -a suffixes=("jbr" "jre" "jbr/Contents/Home")
  local s
  for cand in "${bases[@]}"; do
    [ -n "$cand" ] || continue
    for s in "${suffixes[@]}"; do
      [ -d "$cand/$s/bin" ] && candidates+=("$cand/$s")
    done
  done

  # a plain JDK on PATH
  if command -v javac >/dev/null 2>&1; then
    cand="$(dirname "$(dirname "$(command -v javac)")")"
    [ -d "$cand/bin" ] && candidates+=("$cand")
  fi
  if command -v java >/dev/null 2>&1; then
    cand="$(dirname "$(dirname "$(command -v java)")")"
    [ -d "$cand/bin" ] && candidates+=("$cand")
  fi

  # pick the newest JDK that's still within the supported window
  for cand in "${candidates[@]}"; do
    v="$(java_major "$cand" 2>/dev/null || true)"
    [ -n "$v" ] || continue
    if [ "$v" -ge "$JAVA_MIN" ] && [ "$v" -le "$JAVA_MAX" ] && [ "$v" -gt "$best_v" ]; then
      best="$cand"; best_v="$v"
    elif [ -z "$JAVA_REJECTED" ]; then
      JAVA_REJECTED="$cand (Java $v)"
    fi
  done

  [ -n "$best" ] && { JAVA_FOUND="$best"; return 0; }
  return 1
}

# Echoes a usable keytool, or nothing. Also leaves JAVA_FOUND/JAVA_REJECTED set.
find_keytool() {
  local k

  # explicit override wins
  if [ -n "${KEYTOOL:-}" ]; then
    k="$(posix_path "$KEYTOOL")"
    [ -f "$k" ] && { printf '%s' "$k"; return 0; }
  fi

  if detect_java; then
    for k in "$JAVA_FOUND/bin/keytool" "$JAVA_FOUND/bin/keytool.exe"; do
      [ -f "$k" ] && { printf '%s' "$k"; return 0; }
    done
  fi

  command -v keytool >/dev/null 2>&1 && { command -v keytool; return 0; }
  return 1
}
