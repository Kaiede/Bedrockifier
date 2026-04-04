#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT_PATH="${ROOT_DIR}/Docker/restore-menu.sh"

tmpdir="$(mktemp -d)"
cleanup() {
  rm -rf "${tmpdir}"
}
trap cleanup EXIT

ok_tool="${tmpdir}/fake-ok"
missing_tool="${tmpdir}/fake-missing"

cat > "${ok_tool}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

cmd="$1"
archive="$2"
root="$3"

if [[ "${cmd}" != "unpack" ]]; then
  echo "unexpected command: ${cmd}" >&2
  exit 64
fi

base="$(basename "${archive}")"
stem="${base%.*}"
stem="${stem%.*}"
world="${stem}"
if [[ "${world}" == *.* ]]; then
  world="${world#*.}"
fi

mkdir -p "${root}/${world}"
printf 'restored\n' > "${root}/${world}/restored.txt"
EOF

cat > "${missing_tool}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF

chmod +x "${ok_tool}" "${missing_tool}"

run_case() {
  local name="$1"
  local expected_exit="$2"
  local expected_text="$3"
  shift 3

  local output_file="${tmpdir}/${name}.out"
  local status=0

  if "$@" >"${output_file}" 2>&1; then
    status=0
  else
    status=$?
  fi

  if [[ "${status}" != "${expected_exit}" ]]; then
    echo "FAIL ${name}: expected exit ${expected_exit}, got ${status}" >&2
    sed -n '1,40p' "${output_file}" >&2
    exit 1
  fi

  if ! rg -Fq -- "${expected_text}" "${output_file}"; then
    echo "FAIL ${name}: expected output to contain: ${expected_text}" >&2
    sed -n '1,40p' "${output_file}" >&2
    exit 1
  fi

  echo "PASS ${name}"
}

# Bedrock single-target success
mkdir -p "${tmpdir}/bedrock/worlds" "${tmpdir}/backups-bedrock"
cat > "${tmpdir}/bedrock.yml" <<EOF
containers:
  bedrock:
    - name: bedrock_public
      worlds:
        - ${tmpdir}/bedrock/worlds/PublicSMP
EOF
touch "${tmpdir}/backups-bedrock/PublicSMP.2026-04-03_1200-00.mcworld"
run_case \
  "bedrock-single" 0 "Target: bedrock_public [bedrock] PublicSMP" \
  env TOOL_BIN="${ok_tool}" BACKUP_DIR="${tmpdir}/backups-bedrock" RESTORE_CONFIG_PATH="${tmpdir}/bedrock.yml" \
  "${SCRIPT_PATH}" --file PublicSMP.2026-04-03_1200-00.mcworld --yes

# Java single-target success
mkdir -p "${tmpdir}/java" "${tmpdir}/backups-java"
cat > "${tmpdir}/java.yml" <<EOF
containers:
  java:
    - name: minecraft_public
      worlds:
        - ${tmpdir}/java/PublicSMP
EOF
touch "${tmpdir}/backups-java/PublicSMP.2026-04-03_1200-00.zip"
run_case \
  "java-single" 0 "Target: minecraft_public [java] PublicSMP" \
  env TOOL_BIN="${ok_tool}" BACKUP_DIR="${tmpdir}/backups-java" RESTORE_CONFIG_PATH="${tmpdir}/java.yml" \
  "${SCRIPT_PATH}" --file PublicSMP.2026-04-03_1200-00.zip --yes

# Prefixed multi-target success
mkdir -p "${tmpdir}/multi/public/worlds" "${tmpdir}/multi/private/worlds" "${tmpdir}/backups-multi"
cat > "${tmpdir}/multi.yml" <<EOF
prefixContainerName: true
containers:
  bedrock:
    - name: bedrock_public
      worlds:
        - ${tmpdir}/multi/public/worlds/PublicSMP
    - name: bedrock_private
      worlds:
        - ${tmpdir}/multi/private/worlds/PrivateSMP
EOF
touch "${tmpdir}/backups-multi/bedrock_public.PublicSMP.2026-04-03_1200-00.mcworld"
run_case \
  "prefixed-multi-target" 0 "Target: bedrock_public [bedrock] PublicSMP" \
  env TOOL_BIN="${ok_tool}" BACKUP_DIR="${tmpdir}/backups-multi" RESTORE_CONFIG_PATH="${tmpdir}/multi.yml" \
  "${SCRIPT_PATH}" --file bedrock_public.PublicSMP.2026-04-03_1200-00.mcworld --target bedrock_public --yes

# Ambiguous unprefixed multi-target failure
mkdir -p "${tmpdir}/amb/a/worlds" "${tmpdir}/amb/b/worlds" "${tmpdir}/backups-amb"
cat > "${tmpdir}/amb.yml" <<EOF
containers:
  bedrock:
    - name: bedrock_a
      worlds:
        - ${tmpdir}/amb/a/worlds/SameWorld
    - name: bedrock_b
      worlds:
        - ${tmpdir}/amb/b/worlds/SameWorld
EOF
touch "${tmpdir}/backups-amb/SameWorld.2026-04-03_1200-00.mcworld"
run_case \
  "ambiguous-unprefixed" 1 "The archive matches multiple restore targets." \
  env TOOL_BIN="${ok_tool}" BACKUP_DIR="${tmpdir}/backups-amb" RESTORE_CONFIG_PATH="${tmpdir}/amb.yml" \
  "${SCRIPT_PATH}" --file SameWorld.2026-04-03_1200-00.mcworld --yes

# Extras archive rejection
run_case \
  "extras-archive" 1 "Unable to match the archive to any configured restore target." \
  env TOOL_BIN="${ok_tool}" BACKUP_DIR="${tmpdir}/backups-java" RESTORE_CONFIG_PATH="${tmpdir}/java.yml" \
  "${SCRIPT_PATH}" --file PublicSMP.extras.2026-04-03_1200-00.zip --yes

# Replace-in-place over existing target
mkdir -p "${tmpdir}/replace/worlds/PublicSMP" "${tmpdir}/backups-replace"
printf 'old\n' > "${tmpdir}/replace/worlds/PublicSMP/old.txt"
cat > "${tmpdir}/replace.yml" <<EOF
containers:
  bedrock:
    - name: bedrock_replace
      worlds:
        - ${tmpdir}/replace/worlds/PublicSMP
EOF
touch "${tmpdir}/backups-replace/PublicSMP.2026-04-03_1200-00.mcworld"
run_case \
  "replace-in-place" 0 "Target: bedrock_replace [bedrock] PublicSMP" \
  env TOOL_BIN="${ok_tool}" BACKUP_DIR="${tmpdir}/backups-replace" RESTORE_CONFIG_PATH="${tmpdir}/replace.yml" \
  "${SCRIPT_PATH}" --file PublicSMP.2026-04-03_1200-00.mcworld --yes
if [[ ! -f "${tmpdir}/replace/worlds/PublicSMP/restored.txt" || -e "${tmpdir}/replace/worlds/PublicSMP/old.txt" ]]; then
  echo "FAIL replace-in-place: target was not replaced cleanly" >&2
  exit 1
fi
echo "PASS replace-in-place-filesystem"

# Missing target path after unpack
mkdir -p "${tmpdir}/missing/worlds" "${tmpdir}/backups-missing"
cat > "${tmpdir}/missing.yml" <<EOF
containers:
  bedrock:
    - name: bedrock_missing
      worlds:
        - ${tmpdir}/missing/worlds/PublicSMP
EOF
touch "${tmpdir}/backups-missing/PublicSMP.2026-04-03_1200-00.mcworld"
run_case \
  "missing-target-after-unpack" 1 "configured target path was not created" \
  env TOOL_BIN="${missing_tool}" BACKUP_DIR="${tmpdir}/backups-missing" RESTORE_CONFIG_PATH="${tmpdir}/missing.yml" \
  "${SCRIPT_PATH}" --file PublicSMP.2026-04-03_1200-00.mcworld --yes

# Explicit missing config path
run_case \
  "missing-config-path" 1 "Unable to load restore targets from config.yml." \
  env TOOL_BIN="${ok_tool}" BACKUP_DIR="${tmpdir}/backups-bedrock" RESTORE_CONFIG_PATH="${tmpdir}/does-not-exist.yml" \
  "${SCRIPT_PATH}" --file PublicSMP.2026-04-03_1200-00.mcworld --yes

echo "All restore-menu smoke tests passed."
