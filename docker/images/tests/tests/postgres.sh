#!/bin/bash
source /tests/lib/functions.sh postgres

psql() {
  command psql -h ${POSTGRES_HOST:-postgres} -U vcap "$@"
}

rc=0

cat <<'BANNER'
  ____           _
 |  _ \ ___  ___| |_ __ _ _ __ ___  ___
 | |_) / _ \/ __| __/ _` | '__/ _ \/ __|
 |  __/ (_) \__ \ || (_| | | |  __/\__ \
 |_|   \___/|___/\__\__, |_|  \___||___/
                     |___/
BANNER

echo ">> configuring SHIELD"
cat <<EOF | shield import -
core:  http://${SHIELD_HOST:-core}:8080
token: $SHIELD_AUTH_TOKEN

tenants:
  - name: Default Tenant

    systems:
      - name:   postgres-all
        plugin: postgres
        agent:  ${AGENT_HOST:-agent}:5444
        config:
          pg_host:     ${POSTGRES_HOST:-postgres}
          pg_user:     vcap
          pg_password: ''
          pg_bindir:   /usr/bin
        jobs:
          - name:    postgres-all-daily
            when:    daily 4am
            retain:  2d
            storage: s3
            paused:  true

      - name:   postgres-single
        plugin: postgres
        agent:  ${AGENT_HOST:-agent}:5444
        config:
          pg_host:     ${POSTGRES_HOST:-postgres}
          pg_user:     vcap
          pg_password: ''
          pg_bindir:   /usr/bin
          pg_database: db1
        jobs:
          - name:    postgres-single-daily
            when:    daily 4am
            retain:  2d
            storage: s3
            paused:  true
EOF

##########################################################################

echo "> Postgres - All Databases"

echo ">> setting up test data"
psql postgres <$ROOT/init.sql
psql db1 -c 'SELECT * FROM t_vals ORDER BY ID ASC' >$TMP/db1.dat
psql db2 -c 'SELECT * FROM t_keys ORDER BY ID ASC' >$TMP/db2.dat

echo ">> running backup job"
wait_for_task $(shield run-job postgres-all-daily | jq -r '.task_uuid')

echo ">> trashing test data"
psql db1 -c 'DELETE FROM t_vals'
psql db2 -c 'DELETE FROM t_keys'

echo ">> restoring from backup"
wait_for_task $(restore_latest postgres-all)

echo ">> verifying restored data"
psql db1 -c 'SELECT * FROM t_vals ORDER BY ID ASC' >$TMP/db1.after.dat
psql db2 -c 'SELECT * FROM t_keys ORDER BY ID ASC' >$TMP/db2.after.dat

if ! diff -q $TMP/db1.dat $TMP/db1.after.dat; then
  echo "!! FAIL: db1.t_vals does not match after restore !!"
  diff $TMP/db1.dat $TMP/db1.after.dat
  rc=1
else
  echo "   db1.t_vals matches after restore"
fi

if ! diff -q $TMP/db2.dat $TMP/db2.after.dat; then
  echo "!! FAIL: db2.t_keys does not match after restore !!"
  diff $TMP/db2.dat $TMP/db2.after.dat
  rc=1
else
  echo "   db2.t_keys matches after restore"
fi

echo ">> checking encryption"
check_encryption postgres-all || rc=1

##########################################################################

echo "> Postgres - Single Database"

echo ">> setting up test data"
psql postgres <$ROOT/init.sql
psql db1 -c 'SELECT * FROM t_vals ORDER BY ID ASC' >$TMP/db1.dat
psql db2 -c 'SELECT * FROM t_keys ORDER BY ID ASC' >$TMP/db2.dat

echo ">> running backup job"
wait_for_task $(shield run-job postgres-single-daily | jq -r '.task_uuid')

echo ">> trashing test data"
psql db1 -c 'DELETE FROM t_vals'
psql db2 -c 'DELETE FROM t_keys'

echo ">> restoring from backup"
wait_for_task $(restore_latest postgres-single)

echo ">> verifying restored data"
psql db1 -c 'SELECT * FROM t_vals ORDER BY ID ASC' >$TMP/db1.after.dat
psql db2 -c 'SELECT * FROM t_keys ORDER BY ID ASC' >$TMP/db2.after.dat

if ! diff -q $TMP/db1.dat $TMP/db1.after.dat; then
  echo "!! FAIL: db1.t_vals does not match after restore (single) !!"
  diff $TMP/db1.dat $TMP/db1.after.dat
  rc=1
else
  echo "   db1.t_vals matches after restore (single)"
fi

# db2 should NOT be restored in single-database mode
psql db2 -c 'SELECT * FROM t_keys ORDER BY ID ASC' >$TMP/db2.after.dat
if diff -q $TMP/db2.dat $TMP/db2.after.dat >/dev/null 2>&1; then
  echo "!! FAIL: db2.t_keys was restored but should not have been in single-db mode !!"
  rc=1
else
  echo "   db2.t_keys correctly absent after single-db restore"
fi

echo ">> checking encryption"
check_encryption postgres-single || rc=1

##########################################################################

exit $rc
