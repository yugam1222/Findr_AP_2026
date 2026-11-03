# Findr query timing results

**Measurement status:** This is a partially completed benchmark record. Only the values shown below were actually measured; all other values remain Pending. The recorded timings were collected with PostgreSQL `\\timing` in `psql`, not with `EXPLAIN (ANALYZE, BUFFERS)`. Do not describe them as EXPLAIN execution times.

## Environment record

| Field | Actual value |
|---|---|
| PostgreSQL version | PostgreSQL 18.6 (Postgres.app) |
| OS / machine | macOS, MacBook Pro |
| Dataset size (users) | 2 |
| Dataset size (communities) | 1 |
| Dataset size (items) | 2 |
| Dataset size (claims) | 1 |
| Database name | `findr_test` |
| Benchmark date | 2026-11-03 |
| Dataset generation method | Small manually inserted test fixtures |

## Timing table

Execution times below are the actual elapsed times displayed by `psql` with `\\timing on`. Three runs were recorded for each listed query. R1 is Pending because the earlier measured SELECT was a simpler query and did not match the R1 statement in the current `04_queries.sql` file.

| Query ID | Type | Run 1 (ms) | Run 2 (ms) | Run 3 (ms) | Average (ms) |
|---|---|---:|---:|---:|---:|
| R1 | READ | Pending | Pending | Pending | Pending |
| R2 | READ | Pending | Pending | Pending | Pending |
| R3 | READ | 2.297 | 0.707 | 0.656 | 1.220 |
| R4 | READ | 1.696 | 0.720 | 0.902 | 1.106 |
| R5 | READ | 2.156 | 0.704 | 0.779 | 1.213 |
| R6 | READ | 0.746 | 0.965 | 0.978 | 0.896 |
| R7 | READ | 1.770 | 0.515 | 0.515 | 0.933 |
| W1 | WRITE | Pending | Pending | Pending | Pending |
| W2 | WRITE | Pending | Pending | Pending | Pending |
| W3 | WRITE | Pending | Pending | Pending | Pending |
| W4 | WRITE | Pending | Pending | Pending | Pending |
| W5 | WRITE | Pending | Pending | Pending | Pending |
| W6 | WRITE | Pending | Pending | Pending | Pending |
| W7 | WRITE | Pending | Pending | Pending | Pending |

Average = `(Run 1 + Run 2 + Run 3) / 3`, rounded to three decimal places.

## Result-set and testing notes

- R3 returned one item row in each run.
- R4 returned one LOST item row in each run.
- R5 returned zero rows because the test claim had already been approved, while R5 filters for `PENDING` claims. The SQL executed, but a non-empty pending-claim result was not demonstrated.
- R6 returned one claim row in each run.
- R7 returned zero rows because the test user had no notifications. The SQL executed, but a non-empty notification result was not demonstrated.
- A separate manual workflow test showed a claim moving to `APPROVED`, a handover moving to `COMPLETED`, and the item moving to `RETURNED`. This was a functional manual test, not a benchmark of W4 or W5 from this query catalogue.
- An earlier R1 timing (1.125 ms, 1.373 ms, 0.811 ms; average 1.103 ms) was measured for a different, simpler SELECT statement. It is intentionally excluded from this table because it is not the R1 query currently present in `04_queries.sql`.
- The measured database was created from an earlier schema version in the working repository. The current Version 2 schema in this ZIP includes additional integrity triggers and workflow logic. Therefore, the timings above are preliminary query checks, not evidence that the complete current Version 2 schema and every query have been validated together.
- The dataset is very small and does not represent production-scale performance.

## Interpretation

Among the measured statements, R6 had the lowest average elapsed time (0.896 ms), and R3 had the highest (1.220 ms). These differences are too small and the dataset is too limited to support broad performance conclusions. Repeated runs varied, particularly where the first run was slower than subsequent runs.

No conclusion about index effectiveness, sequential versus index scans, buffer activity, or sort cost is made from these `\\timing` measurements. Use `EXPLAIN (ANALYZE, BUFFERS)` on the exact current query statements, retain the plans in `plans/`, and repeat measurements on the same schema, dataset, machine, and configuration before making those claims.
