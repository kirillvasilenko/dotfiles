---
name: jepsen-on-slice
description: How to deploy a ydbd build to my slice cluster and run jepsen against it, then collect the logs. Use when asked to run jepsen, reproduce a jepsen failure, or deploy a build to the slice.
---

# Jepsen on the slice

Big tests run only on my slice, never on other people's clusters.

## 1. Prepare the slice

1. Build ydbd in the repository you work in and copy it to `~/ydbds/slice/`:

   ```bash
   ./ya make --build relwithdebinfo ydb/apps/ydbd
   cp ydb/apps/ydbd/ydbd ~/ydbds/slice/ydbd
   ```

2. Edit `~/slice/config.yaml` to the config you need. When reproducing a reported problem, use the reporters' config. Log levels go at the end of the file (`log_config: entry:`). `~/slice/config_backup.yaml` is the pristine copy.
3. Deliver the binary and the config:
   - `~/slice/update.sh`, after incrementing `metadata.version` in `config.yaml`.
   - If `update.sh` hangs, `~/slice/install.sh` instead: slower but reliable; set `metadata.version: 0` first.

## 2. Run jepsen

From `~/tools/jepsen.ydb/`:

```bash
lein run test \
  --nodes-file ~/slice/ydb-nodes.txt \
  --db-name /Root/test \
  --no-ssh \
  --concurrency 10n \
  --key-count 15 \
  --max-writes-per-key 1000 \
  --max-txn-length 4 \
  --batch-ops-probability 0.85 \
  --batch-commit-probability 0.5 \
  --ballast-size 1024 \
  --store-type column \
  --time-limit 60
```

Parameters vary. When reproducing a reported problem, use the reporters' exact parameters, keeping `--nodes-file` and `--db-name` of the slice. `10n` means 10 per node in the nodes file, and the default `--rate` caps the run at 100 ops/s.

## 3. Logs

- Jepsen: `~/tools/jepsen.ydb/store/ydb/<timestamp>/` (`jepsen.log`, `history.txt`, `results.edn`).
- ydbd: on every host listed in `config.yaml`, `/Berkanavt/kikimr_31003/logs`, `/Berkanavt/kikimr_31013/logs`, `/Berkanavt/kikimr_31023/logs`; copy them with `scp`.
- If the logs there are big, delete them before an experiment, and clean them after a heavy one so the hosts do not run out of space.

## Slice

- Hosts: `~/slice/ydb-nodes.txt` (and `hosts` in `~/slice/config.yaml`).
- Dashboard: the link is in `~/slice/README`.
