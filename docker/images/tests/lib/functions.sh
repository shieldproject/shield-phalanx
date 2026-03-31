#!/bin/bash
set -eu
test -z "${ERRAND_DEBUG:-}" || set -x
export ROOT=/tests/data/${1:-misc}

shield() {
  command shield --json "$@"
}

wait_for_task() {
  local task=$1
  local timeout=${2:-300}
  local elapsed=0
  echo "   - task $task"
  while true; do
    local status=$(shield task $task 2>/dev/null | jq -r '.status // "not-found"')
    case $status in
    (pending|running) sleep 0.1; elapsed=$((elapsed + 1)) ;;
    (""|scheduled)    sleep 1;   elapsed=$((elapsed + 1)) ;;
    ("done")          echo "   - completed successfully (status=done)."
                      return 0  ;;
    (*)               echo "   - failure / anomaly detected (status=$status)."
                      command shield task $task
                      return 1  ;;
    esac
    if [[ $elapsed -ge $timeout ]]; then
      echo "   - timed out after ${timeout}s waiting for task $task"
      return 1
    fi
  done
}

restore_latest() {
  local target=$1
  local archive_uuid
  archive_uuid=$(shield archives --target "$target" | jq -r '.[0].uuid')
  if [[ -z "$archive_uuid" ]] || [[ "$archive_uuid" == "null" ]]; then
    echo >&2 "   ! no archive found for target '$target'"
    return 1
  fi
  shield restore-archive "$archive_uuid" | jq -r '.uuid'
}

check_encryption() {
    local target=$1
    local archive="$(shield archives --target $target | jq -r '.[0].key')"
    echo "Attempting to validate encryption for archive: $archive"
    s3util get "$archive" test_archive
    local rc=0
    if file --mime-type "test_archive" | grep -q bzip2$; then
        echo "!! Backup Archive is unencrypted - validate encryption process before release !!"
        echo
        rc=1
    else
        echo "Backup archive appears to be encrypted."
        echo
    fi
    rm -f test_archive
    return $rc
}
