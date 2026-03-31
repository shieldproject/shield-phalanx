#!/bin/bash
source /tests/lib/functions.sh etcd
export ETCDCTL_API=3

addKeyVals() {
    local url=$1
    local val1=$2
    local val2=$3
    local val3=$4
    local authOption=$5
    echo "Putting three keys..."
    etcdctl $authOption --endpoints=$url put key1 $val1
    etcdctl $authOption --endpoints=$url put key2 $val2
    etcdctl $authOption --endpoints=$url put key3 $val3
}

trashVals() {
    local url=$1
    local authOption=$2
    echo "Trashing data..."
    etcdctl $authOption --endpoints=$url put key1 valueChanged
    etcdctl $authOption --endpoints=$url del key2
    etcdctl $authOption --endpoints=$url put extraKey shouldNotExist
    echo
}

verifyVals() {
    local url=$1
    local rc=0
    local val1=$2
    local val2=$3
    local val3=$4
    local authOption=$5
    if [[ $(etcdctl $authOption --endpoints=$url get key1 --print-value-only) != "$val1" ]]; then
        echo "!! key1 was not initialized properly"
        rc=1
    else
        echo "Got correct value for key1 - $val1"
    fi

    if [[ $(etcdctl $authOption --endpoints=$url get key2 --print-value-only) != "$val2" ]]; then
        echo "!! key2 was not initialized properly"
        rc=1
    else
        echo "Got correct value for key2 - $val2"
    fi

    if [[ $(etcdctl $authOption --endpoints=$url get key3 --print-value-only) != "$val3" ]]; then
        echo "!! key3 was not initialized properly"
        rc=1
    else
        echo "Got correct value for key3 - $val3"
    fi

    if [[ $(etcdctl $authOption --endpoints=$url get extraKey --print-value-only) != "" ]]; then
        echo "!! Overwrite did not work correctly"
        rc=1
    else
        echo "Overwrite works. extraKey doesn't exist"
    fi

    echo
    return $rc
}

dumpKeys() {
    local url=$1
    local authOption=$2
    echo "Printing all keys and values"
    etcdctl $authOption --endpoints=$url get "" --prefix=true
    echo
}

deleteVals() {
    local url=$1
    local authOption=$2
    echo "Deleting keys and values on endpoint: $url with options: $authOption"
    echo "Testing connection to endpoint before delete operation..."
    etcdctl $authOption --endpoints=$url endpoint status || echo "Failed to connect to endpoint"
    echo "Attempting to delete keys with etcdctl command..."
    etcdctl $authOption --endpoints=$url del "" --prefix=true || echo "Delete operation failed"
    echo "Checking remaining keys after failed delete attempt..."
    etcdctl $authOption --endpoints=$url get "" --prefix=true || echo "Failed to retrieve keys after delete attempt"
    echo "Finished delete operation debug."
    echo
}

runTests() {
    local target=$1
    local url=$2
    local rc=0

    local authOption

    local val1=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)
    local val2=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)
    local val3=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)

    echo -e ">> Setting up test data\n"
    if [ "$target" == "etcd-notls" ]; then
        authOption="--user root:tests"
        deleteVals $url "$authOption"
        etcdctl --endpoints=$url user add root:tests || true
        etcdctl --endpoints=$url user grant-role root root || true
        etcdctl --endpoints=$url auth enable || true
        addKeyVals $url $val1 $val2 $val3 "$authOption"
        dumpKeys $url "$authOption"
    else
        authOption="--cacert=/certs/ca.pem --key=/certs/etcd-tls/key.pem --cert=/certs/etcd-tls/cert.pem"
        deleteVals $url "$authOption"
        addKeyVals $url $val1 $val2 $val3 "$authOption"
        dumpKeys $url "$authOption"
    fi

    echo ">> running backup job"
    wait_for_task $(shield run-job ${target}-daily | jq -r '.task_uuid')
    echo

    echo -e ">> Messing up data\n"
    if [ "$target" == "etcd-notls" ]; then
        trashVals $url "$authOption"
        dumpKeys $url "$authOption"
    else
        trashVals $url "$authOption"
        dumpKeys $url "$authOption"
    fi
    echo

    if ! check_encryption ${target}; then
        rc=1
    fi

    echo ">> restoring from backups"
    wait_for_task $(restore_latest ${target})
    echo

    echo -e ">> Verifying test data\n"
    if [ "$target" == "etcd-notls" ]; then
        verifyVals $url $val1 $val2 $val3 "$authOption"
        rc=$?
        dumpKeys $url "$authOption"
        etcdctl --endpoints=$url --user root:tests auth disable
        etcdctl --endpoints=$url user revoke-role root root
        etcdctl --endpoints=$url user delete root
        deleteVals $url "$authOption"
    else
        verifyVals $url $val1 $val2 $val3 "$authOption"
        rc=$?
        dumpKeys $url "$authOption"
        deleteVals $url "$authOption"
    fi

    return $rc;
}

rc=0
echo ">> configuring SHIELD"
cat <<EOF | spruce merge - | shield import -
---
core:  http://${SHIELD_HOST:-core}:8080
token: $SHIELD_AUTH_TOKEN

tenants:
  - name: Default Tenant

    systems:
      - name:   etcd-notls
        plugin: etcd
        agent:  ${AGENT_HOST:-agent}:5444
        config:
          url:                      http://${ETCD_HOST:-etcd}:2379
          timeout:                  "2"
          overwrite:                true
          auth:                     "Role-Based Authentication"
          username:                 root
          password:                 tests
        jobs:
          - name:    etcd-notls-daily
            when:    daily 1am
            retain:  2d
            storage: s3
            paused:  true

      - name:   etcd-tls
        plugin: etcd
        agent:  ${AGENT_HOST:-agent}:5444
        config:
          url:                      https://${ETCD_TLS_HOST:-etcd-tls}:2479
          timeout:                  "2"
          overwrite:                true
          auth:                     "Certificate-Based Authentication"
          ca_cert:                  (( file "/certs/ca.pem" ))
          client_cert:              (( file "/certs/etcd-tls/cert.pem" ))
          client_key:               (( file "/certs/etcd-tls/key.pem" ))
        jobs:
          - name:    etcd-tls-daily
            when:    daily 1am
            retain:  2d
            storage: s3
            paused:  true
EOF

echo "Testing etcd without tls..."
runTests etcd-notls http://${ETCD_HOST:-etcd}:2379
rc=$?
echo

echo "Testing etcd with tls..."
runTests etcd-tls https://${ETCD_TLS_HOST:-etcd-tls}:2479
rc=$(($rc + $?))

exit $rc
