#!/bin/bash
source /tests/lib/functions.sh consul

setkey() {
  local url=$1
  local key=$2
  local val=$3

  if [[ -z $(getkey $url $key) ]]; then
    echo "   creating new key '$key' with value '$val'"
  else
    echo "   changing key '$key' from '$(getkey $url $key)' -> '$val'"
  fi
  curl -sLk -XPUT $url/v1/kv/$key -d "$val" >/dev/null
}
getkey() {
  curl -sLk $1/v1/kv/$2 | jq -r '.[].Value' | base64 -d
}
delkey() {
  curl -sLk $1/v1/kv/$2 -X DELETE
}
dumpkeys() {
  local url=$1
  shift
  for k in "$@"; do
    echo "    - $k = '$(getkey $url $k)'"
  done
}

run_tests() {
	local target=$1
	local url=$2
	local rc=0

	echo ">> setting up test data"
	setkey $url test1 foo
	setkey $url test2 bar
	delkey $url test3
	dumpkeys $url test1 test2 test3
	echo

	echo ">> running backup job"
	wait_for_task $(shield run-job ${target}-daily | jq -r '.task_uuid')
	echo

	if ! check_encryption ${target}; then
		rc=1
	fi

	echo ">> trashing the data"
	setkey $url test1 "this is incorrect"
	setkey $url test3 new-key
	dumpkeys $url test1 test2 test3
	echo

	echo ">> restoring from backups"
	wait_for_task $(restore_latest ${target})
	echo

	echo ">> verifying data, post-restore"
	dumpkeys $url test1 test2 test3

	local t1 t2 t3
	t1=$(getkey $url test1)
	t2=$(getkey $url test2)
	t3=$(getkey $url test3)

	if [[ "$t1" != "foo" ]]; then
		echo "!! FAIL: test1 should be 'foo', got '$t1'"
		rc=1
	else
		echo "   test1 correctly restored to 'foo'"
	fi

	if [[ "$t2" != "bar" ]]; then
		echo "!! FAIL: test2 should be 'bar', got '$t2'"
		rc=1
	else
		echo "   test2 correctly restored to 'bar'"
	fi

	if [[ -n "$t3" ]]; then
		echo "!! FAIL: test3 should be absent after restore, got '$t3'"
		rc=1
	else
		echo "   test3 correctly absent after restore"
	fi

	return $rc
}

rc=0

cat <<'BANNER'
   ____                      _
  / ___|___  _ __  ___ _   _| |
 | |   / _ \| '_ \/ __| | | | |
 | |__| (_) | | | \__ \ |_| | |
  \____\___/|_| |_|___/\__,_|_|
BANNER

echo ">> configuring SHIELD"
cat <<EOF | shield import -
core:  http://${SHIELD_HOST:-core}:8080
token: $SHIELD_AUTH_TOKEN

tenants:
  - name: Default Tenant

    systems:
      - name:   consul-notls
        plugin: consul
        agent:  ${AGENT_HOST:-agent}:5444
        config:
          host: http://${CONSUL_HOST:-consul}:8500
        jobs:
          - name:    consul-notls-daily
            when:    daily 4am
            retain:  2d
            storage: s3
            paused:  true

      - name:   consul-tls
        plugin: consul
        agent:  ${AGENT_HOST:-agent}:5444
        config:
          host:                https://${CONSUL_HOST:-consul}:8501
          skip_ssl_validation: yes
        jobs:
          - name:    consul-tls-daily
            when:    daily 4am
            retain:  2d
            storage: s3
            paused:  true
EOF
echo

echo ">> Testing Consul (no TLS)"
run_tests consul-notls http://${CONSUL_HOST:-consul}:8500
rc=$?

echo ">> Testing Consul (TLS)"
run_tests consul-tls https://${CONSUL_HOST:-consul}:8501
rc=$(($rc + $?))

exit $rc
