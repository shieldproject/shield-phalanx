SHIELD Phalanx
==============

Welcome to **Phalanx**, a bespoke BOSH release for testing the
full-stack functionality of Stark & Wayne's [SHIELD][1] backup
solution.


Methodology
-----------

The gist of Phalanx is this: spin a bunch of data systems, run a
handful of SHIELDs with different configurations, and make sure
that backups and (more importantly) restore operations work!


See It Live!
------------

<http://ci.vsphere.starkandwayne.com/teams/main/pipelines/shield>


Current Scope of Tests
----------------------

Phalanx currently exercises the following parts of the SHIELD
distribution.

### The `postgres` Plugin

Two databases are created, and filled with some data.
Two tests are then carried out - a backup/restore of all
databases, and a backup/restore of just one of the databases.

### The `mysql` Plugin

Two databases are created, and filled with some data.
Two tests are then carried out - a backup/restore of all
databases, and a backup/restore of just one of the databases.

### The `consul` Plugin

Two keys are created in the remote Consul Key-Value store, via the
remote HTTP API (on port 8500).  Then, a backup is performed
against Consul, and the keys are altered.  After the backup is
restored, we check to make sure the keys revert to their original
values.


Deploying it Yourself
---------------------

If you want to do in-depth SHIELD development, you may want to
deploy your own copy of Phalanx, on a BOSH-lite.  Here's the steps
to get you started.

First, generate a manifest:

```
./templates/make_manifest
```

Then, you're going to need to provide a release tarball of the
SHIELD you want to test.  From your SHIELD repository, run:

```
make release VERSION=0.9.2-rc.3        # change version as needed
cp artifacts/shield-server-linux-amd64.tar.gz \
   path/to/phalanx/src/shield-rc/
```

Then, cut a new (development) BOSH release and deploy your
manifest:

```
bosh create release --force
bosh upload release
bosh -n deploy
```

Once that's done, just run the `tests` errand:

```
bosh run errand tests
```

If things don't turn out well, you may want to run the errand with
the `--keep-alive` flag, and then `bosh ssh` into the `tests/0`
instance and poke around.


Writing new Tests
-----------------

Tests exist as scripts inside of the
`/var/vcap/jobs/run-tests/tests` directory on the errand VM.  All
you have to do to create a new test is add it to the `run-tests`
job spec, and create the files.

Here's a template script to get you started!

```
#!/bin/bash
source /var/vcap/jobs/run-tests/lib/functions system-name

rc=0
echo "> My New Test"
echo ">> setting up test data"
# FIXME: set up the data

echo ">> configuring SHIELD"
shield create-target <<EOF | jq -r
{
  "name"     : "foo",
  "summary"  : "Foo",
  "plugin"   : "foo",
  "endpoint" : "{}",
  "agent"    : "$TARGET:5444"
}
EOF
shield create-job <<EOF | jq -r
{
  "name"      : "foo-daily",
  "summary"   : "Foo",
  "paused"    : true,
  "retention" : "$RETENTION_UUID",
  "schedule"  : "$SCHEDULE_UUID",
  "store"     : "$STORE_UUID",
  "target"    : "$(shield target foo | jq -r '.uuid')"
}
EOF

echo ">> running backup job"
wait_for_task $(shield run $(shield job foo-daily | jq -r '.uuid') | jq -r '.task_uuid')

echo ">> trashing the data"
# FIXME: trash the data by deleting stuff, changing stuff, etc.

echo ">> restoring from backups"
wait_for_task $(shield restore $(shield archives -t $(shield target foo | jq -r '.uuid') | jq -r '.[0].uuid') | jq -r '.task_uuid')

# FIXME: validate the data, post-restore,
# FIXME: setting rc=<non-zero> on failure.

exit $rc;
```


Future Work
-----------

The following tests need to be conceptualized and implemented.

- A test of the `consul` plugin, against a Consul Key-Value store
  that requires HTTP Basic Authentication.
- A test of the `mongo` plugin, against a MongoDB instance that
  requires authentication.
- Tests for all of the following plugins:
  - docker-postgres
  - elasticsearch
  - rabbitmq-broker
  - redis-broker
  - s3
  - scality
  - xtrabackup


[1]: https://github.com/starkandwayne/shield
