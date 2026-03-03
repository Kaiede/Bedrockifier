#!/usr/bin/env bash
set -euo pipefail

export TERM="${TERM:-xterm-256color}"

BACKUP_DIR="${BACKUP_DIR:-/backups}"
LEVEL_NAME="${LEVEL_NAME:-bedrock}"
DEFAULT_RESTORE_DEST="${DEFAULT_RESTORE_DEST:-${RESTORE_DEST:-/server/worlds/${LEVEL_NAME}}}"
STAMP="${STAMP:-$(date +'%Y-%m-%d_%H%M-%S')}"
RESTORE_UID="${RESTORE_UID:-}"
RESTORE_GID="${RESTORE_GID:-}"
RESTORE_MODE="${RESTORE_MODE:-}"

DIALOG_BIN="${DIALOG_BIN:-dialog}"
DIALOG_HEIGHT="${DIALOG_HEIGHT:-20}"
DIALOG_WIDTH="${DIALOG_WIDTH:-100}"
DIALOG_MENU_HEIGHT="${DIALOG_MENU_HEIGHT:-12}"
INTRO_HEIGHT="${INTRO_HEIGHT:-13}"
INTRO_WIDTH="${INTRO_WIDTH:-72}"
NON_INTERACTIVE=0
OVERWRITE=0
ASSUME_YES=0
RESTORE_FILE=""
INTERACTIVE=1

usage() {
  cat <<'EOF'
Usage: restore-menu.sh [options]

Interactive restore (default):
  restore-menu.sh

Non-interactive restore:
  restore-menu.sh --file <backup.mcworld|backup.zip> [--overwrite] --yes

Options:
  -f, --file <path>   Backup file to restore (name in BACKUP_DIR or a path)
  -o, --overwrite     Delete and overwrite the destination if it exists
  -y, --yes           Confirm the restore when running non-interactively
  -h, --help          Show this help
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -f|--file)
        if [[ $# -lt 2 || -z "${2:-}" ]]; then
          echo "Missing value for $1" >&2
          usage >&2
          exit 2
        fi
        RESTORE_FILE="$2"
        shift 2
        ;;
      --file=*)
        RESTORE_FILE="${1#*=}"
        shift
        ;;
      -o|--overwrite)
        OVERWRITE=1
        shift
        ;;
      -y|--yes)
        ASSUME_YES=1
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      --)
        shift
        break
        ;;
      *)
        echo "Unknown option: $1" >&2
        usage >&2
        exit 2
        ;;
    esac
  done

  if [[ -n "$RESTORE_FILE" ]]; then
    NON_INTERACTIVE=1
    INTERACTIVE=0
  fi

  if ((NON_INTERACTIVE)) && ((ASSUME_YES == 0)); then
    echo "Non-interactive restore requires --yes to proceed." >&2
    usage >&2
    exit 2
  fi
}

cleanup_terminal() {
  # Restore terminal state in case dialog exits without clearing.
  if command -v "$DIALOG_BIN" >/dev/null 2>&1; then
    "$DIALOG_BIN" --clear || true
  fi
  if command -v tput >/dev/null 2>&1; then
    tput rmcup || true
    tput sgr0 || true
    tput op || true
    tput cnorm || true
  fi
  if command -v stty >/dev/null 2>&1; then
    stty sane || true
  fi
  printf '\033[?1049l' || true
  clear || true
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1" >&2
    exit 1
  }
}

parse_args "$@"

if ((INTERACTIVE)); then
  require_cmd "$DIALOG_BIN"
fi
require_cmd unzip
require_cmd stat
trap cleanup_terminal EXIT

resolve_restore_owner() {
  local uid gid owner

  uid="$RESTORE_UID"
  gid="$RESTORE_GID"

  if [[ -z "$uid" || -z "$gid" ]]; then
    if owner="$(stat -c '%u:%g' /server 2>/dev/null)"; then
      uid="${uid:-${owner%%:*}}"
      gid="${gid:-${owner##*:}}"
    fi
  fi

  uid="${uid:-1000}"
  gid="${gid:-1000}"

  printf '%s:%s' "$uid" "$gid"
}

apply_restore_owner() {
  local dest="$1"
  local owner

  owner="$(resolve_restore_owner)"
  chown -R "$owner" "$dest"
}

apply_restore_permissions() {
  local dest="$1"

  if [[ -z "$RESTORE_MODE" ]]; then
    return 0
  fi

  chmod -R -- "$RESTORE_MODE" "$dest"
}

collect_backups() {
  local -a files
  shopt -s nullglob
  files=("${BACKUP_DIR}"/*.mcworld "${BACKUP_DIR}"/*.zip)
  shopt -u nullglob
  if ((${#files[@]} == 0)); then
    return 0
  fi

  for f in "${files[@]}"; do
    printf '%s %s\n' "$(stat -c '%Y' "$f")" "$f"
  done | sort -rn | cut -d' ' -f2-
}

world_name_from_file() {
  local file="$1"
  local base
  local suffix

  base="$(basename "$file")"
  base="${base%.mcworld}"
  base="${base%.zip}"

  if [[ "$base" == *.* ]]; then
    suffix="${base##*.}"
    if [[ "$suffix" =~ ^[0-9]{8}[-_][0-9]{6}$ ]] || \
       [[ "$suffix" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{4}-[0-9]{2}$ ]] || \
       [[ "$suffix" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{6}$ ]]; then
      base="${base%.*}"
    fi
  fi

  printf '%s' "$base"
}

restore_dest_for_backup() {
  local backup_file="$1"
  local world

  world="$(world_name_from_file "$backup_file")"
  if [[ -n "$world" ]]; then
    printf '/server/worlds/%s' "$world"
  else
    printf '%s' "$DEFAULT_RESTORE_DEST"
  fi
}

resolve_archive_path() {
  local backup_ref="$1"

  if [[ "$backup_ref" == */* ]]; then
    printf '%s' "$backup_ref"
  else
    printf '%s/%s' "$BACKUP_DIR" "$backup_ref"
  fi
}

notify() {
  local text="$1"

  if ((INTERACTIVE)); then
    "$DIALOG_BIN" --clear --msgbox "$text" "$DIALOG_HEIGHT" "$DIALOG_WIDTH" || true
  else
    printf '%b\n' "$text"
  fi
}

notify_error() {
  local text="$1"

  if ((INTERACTIVE)); then
    "$DIALOG_BIN" --clear --msgbox "$text" "$DIALOG_HEIGHT" "$DIALOG_WIDTH" || true
  else
    printf 'ERROR: %b\n' "$text" >&2
  fi
}

select_backup() {
  local -a files menu_items
  mapfile -t files < <(collect_backups)

  if ((${#files[@]} == 0)); then
    notify "No .mcworld or .zip backups found in ${BACKUP_DIR}."
    return 1
  fi

  menu_items=()
  for f in "${files[@]}"; do
    bn="$(basename "$f")"
    size_bytes="$(stat -c '%s' "$f")"
    size_h="$(numfmt --to=iec --suffix=B "$size_bytes")"
    mod_time="$(stat -c '%y' "$f" | cut -d. -f1)"
    menu_items+=("$bn" "${mod_time}  ${size_h}")
  done

  set +e
  local choice
  choice=$(
    "$DIALOG_BIN" --clear --stdout --title "Select Backup" \
      --menu "Choose a backup file:" "$DIALOG_HEIGHT" "$DIALOG_WIDTH" "$DIALOG_MENU_HEIGHT" \
      "${menu_items[@]}"
  )
  local status=$?
  set -e
  if ((status != 0)); then
    return 1
  fi
  printf '%s' "$choice"
}

confirm_action() {
  local backup="$1"
  local dest="$2"
  set +e
  "$DIALOG_BIN" --clear --yesno \
    "Restore:\n  ${backup}\n\nDestination:\n  ${dest}\n\nProceed?" "$DIALOG_HEIGHT" "$DIALOG_WIDTH"
  local status=$?
  set -e
  return $status
}

restore_backup() {
  local backup_file="$1"
  local action="$2"

  local archive
  local dest
  local backup_label

  archive="$(resolve_archive_path "$backup_file")"
  backup_label="$(basename "$backup_file")"
  dest="$(restore_dest_for_backup "$backup_file")"

  if [[ ! -f "$archive" ]]; then
    notify_error "Backup file not found: ${archive}"
    return 1
  fi

  if [[ -d "$dest" ]]; then
    if [[ "$action" == "move" ]]; then
      local renamed="${dest}.${STAMP}.original"
      mv -- "$dest" "$renamed"
    else
      rm -rf -- "$dest"
    fi
  fi

  mkdir -p "$dest"

  case "$archive" in
    *.mcworld|*.zip)
      unzip -o "$archive" -d "$dest" >/dev/null
      ;;
    *)
      notify_error "Unsupported backup format: ${backup_label}\n\nSupported: .mcworld, .zip"
      return 1
      ;;
  esac

  if ! apply_restore_owner "$dest"; then
    notify_error "Restore completed, but failed to set ownership on:\n  ${dest}\n\nCheck RESTORE_UID/RESTORE_GID and permissions."
    return 1
  fi

  if ! apply_restore_permissions "$dest"; then
    notify_error "Restore completed, but failed to set permissions on:\n  ${dest}\n\nCheck RESTORE_MODE and permissions."
    return 1
  fi

  notify "Restore completed.\n\nBackup: ${backup_label}\nDestination: ${dest}"
}

main() {
  if ((NON_INTERACTIVE)); then
    backup_file="$RESTORE_FILE"
    restore_dest="$(restore_dest_for_backup "$backup_file")"
    if [[ -d "$restore_dest" ]]; then
      if ((OVERWRITE)); then
        action="overwrite"
      else
        action="move"
      fi
    else
      action="create"
    fi

    if ! restore_backup "$backup_file" "$action"; then
      notify_error "Restore failed for: $(basename "$backup_file")"
      exit 1
    fi
    exit 0
  fi

  "$DIALOG_BIN" --clear --msgbox "===============================\n  Minecraft Bedrock Restore\n===============================\n\nThis tool restores a world backup (.mcworld or .zip)\ninto the server's worlds folder.\n\n*** IMPORTANT ***\nSTOP THE BEDROCK SERVER BEFORE RESTORING A BACKUP." "$INTRO_HEIGHT" "$INTRO_WIDTH" || true

  backup_file="$(select_backup)" || { clear; exit 0; }
  restore_dest="$(restore_dest_for_backup "$backup_file")"

  if [[ -d "$restore_dest" ]]; then
    set +e
    rename_target="${restore_dest}.${STAMP}.original"
    action=$(
      "$DIALOG_BIN" --clear --stdout --title "Existing World" \
        --menu "If the world exists, choose what to do:" "$DIALOG_HEIGHT" "$DIALOG_WIDTH" 2 \
        "move" "Move existing to ${rename_target} (recommended)" \
        "overwrite" "Delete and overwrite"
    )
    status=$?
    set -e
    if ((status != 0)); then
      clear
      exit 0
    fi
  else
    action="create"
  fi

  confirm_action "$backup_file" "$restore_dest" || { clear; exit 0; }
  if ! restore_backup "$backup_file" "$action"; then
    notify_error "Restore failed for: ${backup_file}"
  fi
  clear || true
}

main
