#!/bin/bash
source /tests/lib/functions.sh mongodb

mongo() {
	command mongosh --quiet "mongodb://${MONGODB_HOST:-mongodb}" "$@"
}

rc=0

cat <<'BANNER'
  __  __                         ____  ____
 |  \/  | ___  _ __   __ _  ___|  _ \| __ )
 | |\/| |/ _ \| '_ \ / _` |/ _ \ | | |  _ \
 | |  | | (_) | | | | (_| | (_) | |_| | |_) |
 |_|  |_|\___/|_| |_|\__, |\___/|____/|____/
                      |___/
BANNER

echo ">> configuring SHIELD"
cat <<EOF | shield import -
core:  http://${SHIELD_HOST:-core}:8080
token: $SHIELD_AUTH_TOKEN

tenants:
  - name: Default Tenant

    systems:
      - name:   mongodb-all
        plugin: mongo
        agent:  ${AGENT_HOST:-agent}:5444
        config:
          mongo_host:   ${MONGODB_HOST:-mongodb}
          mongo_bindir: /usr/bin
        jobs:
          - name:    mongodb-all-daily
            when:    daily 4am
            retain:  2d
            storage: s3
            paused:  true
EOF
echo

echo ">> setting up test data"
mongo --file $ROOT/init.js
mongo --eval 'db.collection.find({})' >$TMP/db.dat
echo "   initial contents of the database:"
sed -e 's/^/    /' <$TMP/db.dat
echo

echo ">> running backup job"
wait_for_task $(shield run-job mongodb-all-daily | jq -r '.task_uuid')
echo

if ! check_encryption mongodb-all; then
	rc=1
fi

echo ">> trashing the data"
echo "   deleting all of the data out of 'db'"
mongo --eval 'db.collection.deleteMany({})'
echo "   contents of the database are now:"
mongo --eval 'db.collection.find({})' | sed -e 's/^/    /'
echo

echo ">> restoring from backups"
wait_for_task $(restore_latest mongodb-all)
echo

echo ">> verifying data, post-restore"
echo "   contents of 'db':"
mongo --eval 'db.collection.find({})' | sed -e 's/^/    /'

mongo --eval 'db.collection.find({})' >$TMP/db.post

if ! diff -u $TMP/db.dat $TMP/db.post &>/dev/null; then
	echo "!! db was not properly restored!"
	echo
	diff -u $TMP/db.dat $TMP/db.post || true
	echo
	rc=1
else
	echo "   db matches after restore"
fi

exit $rc
