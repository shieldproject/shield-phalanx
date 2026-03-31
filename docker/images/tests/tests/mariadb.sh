#!/bin/bash
source /tests/lib/functions.sh mariadb

mysql() {
  command mysql -h ${MARIADB_HOST:-mariadb} -u vcap -pletmein "$@"
}

rc=0

cat <<'BANNER'
  __  __            _       ____  ____
 |  \/  | __ _ _ __(_) __ _|  _ \| __ )
 | |\/| |/ _` | '__| |/ _` | | | |  _ \
 | |  | | (_| | |  | | (_| | |_| | |_) |
 |_|  |_|\__,_|_|  |_|\__,_|____/|____/
BANNER

echo ">> configuring SHIELD"
cat <<EOF | shield import -
core:  http://${SHIELD_HOST:-core}:8080
token: $SHIELD_AUTH_TOKEN

tenants:
  - name: Default Tenant

    systems:
      - name:   mysql-all
        plugin: mysql
        agent:  ${AGENT_HOST:-agent}:5444
        config:
          mysql_host:     ${MARIADB_HOST:-mariadb}
          mysql_user:     vcap
          mysql_password: letmein
          mysql_bindir:   /usr/bin
        jobs:
          - name:    mysql-all-daily
            when:    daily 4am
            retain:  2d
            storage: s3
            paused:  true

      - name:   mysql-single
        plugin: mysql
        agent:  ${AGENT_HOST:-agent}:5444
        config:
          mysql_host:     ${MARIADB_HOST:-mariadb}
          mysql_user:     vcap
          mysql_password: letmein
          mysql_bindir:   /usr/bin
          mysql_database: db1
        jobs:
          - name:    mysql-single-daily
            when:    daily 4am
            retain:  2d
            storage: s3
            paused:  true
EOF

##########################################################################

echo "> MariaDB - All Databases"

echo ">> setting up test data"
mysql <$ROOT/init.sql
mysql db1 -e 'SELECT * FROM t_vals ORDER BY ID ASC' >$TMP/db1.dat
mysql db2 -e 'SELECT * FROM t_keys ORDER BY ID ASC' >$TMP/db2.dat

echo ">> running backup job"
wait_for_task $(shield run-job mysql-all-daily | jq -r '.task_uuid')

echo ">> trashing test data"
mysql db1 -e 'DELETE FROM t_vals'
mysql db2 -e 'DELETE FROM t_keys'

echo ">> restoring from backup"
wait_for_task $(restore_latest mysql-all)

echo ">> verifying restored data"
mysql db1 -e 'SELECT * FROM t_vals ORDER BY ID ASC' >$TMP/db1.after.dat
mysql db2 -e 'SELECT * FROM t_keys ORDER BY ID ASC' >$TMP/db2.after.dat

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
check_encryption mysql-all || rc=1

##########################################################################

echo "> MariaDB - Single Database"

echo ">> setting up test data"
mysql <$ROOT/init.sql
mysql db1 -e 'SELECT * FROM t_vals ORDER BY ID ASC' >$TMP/db1.dat
mysql db2 -e 'SELECT * FROM t_keys ORDER BY ID ASC' >$TMP/db2.dat

echo ">> running backup job"
wait_for_task $(shield run-job mysql-single-daily | jq -r '.task_uuid')

echo ">> trashing test data"
mysql db1 -e 'DELETE FROM t_vals'
mysql db2 -e 'DELETE FROM t_keys'

echo ">> restoring from backup"
wait_for_task $(restore_latest mysql-single)

echo ">> verifying restored data"
mysql db1 -e 'SELECT * FROM t_vals ORDER BY ID ASC' >$TMP/db1.after.dat
mysql db2 -e 'SELECT * FROM t_keys ORDER BY ID ASC' >$TMP/db2.after.dat

if ! diff -q $TMP/db1.dat $TMP/db1.after.dat; then
  echo "!! FAIL: db1.t_vals does not match after restore (single) !!"
  diff $TMP/db1.dat $TMP/db1.after.dat
  rc=1
else
  echo "   db1.t_vals matches after restore (single)"
fi

# db2 should NOT be restored in single-database mode
mysql db2 -e 'SELECT * FROM t_keys ORDER BY ID ASC' >$TMP/db2.after.dat
if diff -q $TMP/db2.dat $TMP/db2.after.dat >/dev/null 2>&1; then
  echo "!! FAIL: db2.t_keys was restored but should not have been in single-db mode !!"
  rc=1
else
  echo "   db2.t_keys correctly absent after single-db restore"
fi

echo ">> checking encryption"
check_encryption mysql-single || rc=1

##########################################################################

exit $rc
