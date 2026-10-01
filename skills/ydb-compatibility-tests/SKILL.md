---
name: ydb-compatibility-tests
description: How to run and debug YDB compatibility tests (ydb/tests/compatibility) with ydbd binaries of my choice, get backtraces and logs out of them, and reproduce a failure. Use when asked to debug, reproduce or run a compatibility, rolling upgrade/downgrade or mixed-version test.
---

# Debugging YDB compatibility tests

The tests do not run the ydbd built from the local sources: they take prebuilt binaries of the
versions under test (`ydb/tests/library/compatibility/binaries/ydbd-{init,inter,target}`). Point them
at your own builds instead.

## 1. Build the binary you need

Add whatever logs you need to the sources, then build ydbd and copy it out; `cp -L`, because the
build output is a symlink into the build cache:

```bash
./ya make --build relwithdebinfo ydb/apps/ydbd
mkdir -p ~/ydbds/<name>
cp -L ydb/apps/ydbd/ydbd ~/ydbds/<name>/ydbd
```

`~/ydbds/` keeps one directory per build, e.g. `~/ydbds/stable-26-1-1/`, `~/ydbds/my-debug/`.

## 2. Point the test at the binaries

```bash
export YDB_INIT_BINARY_PATH=~/ydbds/<older>/ydbd
export YDB_INTER_BINARY_PATH=~/ydbds/<newer>/ydbd
export YDB_CURRENT_BINARY_PATH=~/ydbds/<current>/ydbd
```

The test ids keep the names of the default versions (they come from the `ydbd-*-name` files), only
the binaries change.

Start with the same binary on both sides (all variables pointing to one build). If the failure
reproduces there, it is not about version compatibility, and the debugging is much simpler.

## 3. Get something out of a crash

Without these a crashed node leaves nothing useful:

```bash
export YDB_ENABLE_SIGNAL_BACKTRACE=1
ulimit -c unlimited
```

## 4. Logs

The cluster runs at NOTICE by default. Raise the components you need right in the test code, in the
`setup_cluster(...)` call of the test:

```python
from ydb.tests.library.harness.util import LogLevels

yield from self.setup_cluster(
    ...,
    additional_log_configs={"KQP_CHANNELS": LogLevels.TRACE},
)
```

Without touching the code: `export YDB_ADDITIONAL_LOG_CONFIGS=KQP_CHANNELS:TRACE,KQP_EXECUTER:DEBUG`
(or `YDB_DEFAULT_LOG_LEVEL` for everything).

Node logs are in the test output directory, `cluster/node_<N>/logfile_*.log`; the pytest log next to
it has the client side (SDK requests with session ids, per-thread progress).

## 5. Run one instance

Run only the parametrization that uses the binaries you set, not the whole suite:

```bash
./ya make --build relwithdebinfo -tA ydb/tests/compatibility/<dir> \
    -F '<test_file>.py::<TestClass>::<test_name>[<param id>]' 2>&1 | tail
```

Repeat with `--test-retries N` for a flaky failure.
