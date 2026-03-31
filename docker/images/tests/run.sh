#!/bin/bash
set -euo pipefail
exec 2>&1
test -z "${ERRAND_DEBUG:-}" || set -x

export SHIELD_HOST="${SHIELD_HOST:-core}"
export AGENT_HOST="${AGENT_HOST:-agent}"
export TARGET="${SHIELD_HOST}"
export TMP=/tmp

echo "################################################################"
echo "#"
echo "# SHIELD at ${SHIELD_HOST}"
echo "#"
echo "################################################################"
echo

export AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID:-rustfsadmin}"
export AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY:-rustfsadmin}"
export AWS_REGION="${AWS_REGION:-us-east-1}"
export S3_ENDPOINT="${S3_ENDPOINT:-http://rustfs:9000}"
export S3_BUCKET=$(dd if=/dev/urandom bs=1 count=32 2>/dev/null | sha1sum | awk '{print $1}')-phalanx
echo "CREATING S3 BUCKET '$S3_BUCKET'"
echo "> Creating bucket '$S3_BUCKET' at ${S3_ENDPOINT}"
s3util create-bucket
echo

echo "CONFIGURING SHIELD AT ${SHIELD_HOST}"
echo "> Targeting backend at ${SHIELD_HOST}"

shield api test http://${SHIELD_HOST}:8080
export SHIELD_CORE=test
export SHIELD_TENANT="Default Tenant"

export SHIELD_CORE_MASTER="${SHIELD_CORE_MASTER:-sekrit}"
shield init || shield unlock

shield login -u smoke -p tests
SHIELD_AUTH_TOKEN=$(shield create-auth-token t$(date +"%Y%m%d%H%M%S"))
export SHIELD_AUTH_TOKEN

cat <<EOF | shield import -
core: http://${SHIELD_HOST}:8080
token: $SHIELD_AUTH_TOKEN

tenants:
  - name: Default Tenant

    storage:
      - name: s3
        plugin: s3
        agent: ${AGENT_HOST}:5444
        config:
          s3_host:            ${S3_ENDPOINT}
          access_key_id:      ${AWS_ACCESS_KEY_ID}
          secret_access_key:  ${AWS_SECRET_ACCESS_KEY}
          bucket:             $S3_BUCKET
          prefix:             ph/al/an/x
EOF

echo "RUNNING TARGET TESTS"
failed=0
rm -f $TMP/FAILURE $TMP/SUCCESS
for run in /tests/tests/*; do
    job=${run##*/}
    chmod 0755 $run
    if ! $run $*; then
        failed=$(( failed + 1 ))
        echo "$job failed" | tr a-z A-Z
        echo "- $job failed" >>$TMP/FAILURE
    else
        echo
        echo "$job succeeded" | tr a-z A-Z
        echo "- $job OK" >>$TMP/SUCCESS
        echo
    fi
done
echo

echo
echo "CLEANING UP S3 BUCKET '$S3_BUCKET'"
echo "> Removing bucket '$S3_BUCKET' (and all of its files)"
s3util delete-bucket

echo
echo
echo "DONE"
echo "  UBUNTU_RELEASE : ${UBUNTU_RELEASE:-unknown}"
echo "  SHIELD_BRANCH  : ${SHIELD_BRANCH:-unknown}"
echo
if [[ $failed -eq 0 ]]; then
    echo "ALL TESTS PASSED"
    echo "----------------------------------"
    cat $TMP/SUCCESS
    echo "----------------------------------"
    echo
    echo "SHIELD IS OKAY TO RELEASE"
    exit 0
else
    echo "$failed TEST(S) FAILED!"
    echo "----------------------------------"
    cat $TMP/FAILURE
    echo "----------------------------------"
    echo
    echo "SHIELD CANNOT BE RELEASED UNTIL THIS IS FIXED"
    exit 1
fi
