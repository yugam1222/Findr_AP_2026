# Benchmark instructions (PostgreSQL)

## 1. Set up a reproducible test database

1. Install/use a PostgreSQL version accepted by your course (the schema targets PostgreSQL 14+).
2. Create a separate, disposable database for the milestone.
3. Run `03_schema.sql` in that empty database.
4. Insert representative test data for users, communities, memberships, items, images, claims, handovers, and notifications. Keep the dataset unchanged between comparable runs.
5. Record PostgreSQL version, machine/OS, row counts, and date in `05_query_timings.md`.

Example:

```bash
createdb findr_dbms_test
psql -d findr_dbms_test -f 03_schema.sql
```

## 2. Define psql variables

`04_queries.sql` uses psql variable syntax such as `:'community_id'`. Define valid IDs and sample values in a local psql session before running a query. Example only (replace with IDs and values that exist in your own test database):

```sql
\set community_id '00000000-0000-0000-0000-000000000001'
\set user_id '00000000-0000-0000-0000-000000000002'
\set item_id '00000000-0000-0000-0000-000000000003'
\set finder_id '00000000-0000-0000-0000-000000000002'
\set claimant_id '00000000-0000-0000-0000-000000000004'
\set category_id '00000000-0000-0000-0000-000000000005'
\set reporter_id '00000000-0000-0000-0000-000000000002'
\set keyword 'wallet'
\set title 'Black wallet'
\set description 'Black wallet found near library'
\set event_date '2026-11-01'
\set location_label 'Near library entrance'
\set latitude ''
\set longitude ''
\set report_type 'FOUND'
\set image_url 'https://example.invalid/test-image.jpg'
\set notification_id '00000000-0000-0000-0000-000000000006'
\set claim_id '00000000-0000-0000-0000-000000000007'
```

These are placeholder examples, not real records. Use valid IDs from your own database. W3 must only be run after the application/backend has verified the claimant's submitted answer against the stored password hash; the raw answer and expected hash must never be exposed in public queries.

## 3. READ query timings

For each R1–R7 query:

1. Copy the query into a separate test script.
2. Prefix it with `EXPLAIN (ANALYZE, BUFFERS)`.
3. Run it three times with the same parameters and dataset.
4. Record the `Execution Time` in milliseconds for each run.
5. Save the full plan output as `plans/R1_run1.txt`, `plans/R1_run2.txt`, etc.

Example:

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT ...;
```

## 4. WRITE query timings

`EXPLAIN ANALYZE` executes data-modifying statements. Use only a disposable test database and restore the required starting state before each measured run.

- W1: use a fresh test report each run, or wrap the statement in `BEGIN` / `ROLLBACK`.
- W2: use an existing test item owned by the supplied reporter; roll back or remove the inserted image between runs.
- W3: backend verification is a prerequisite. Use a fresh eligible found report/claimant state for each run; roll back or reset the test state.
- W4: each run requires a pending claim and an item in `CLAIM_PENDING`. It approves the claim, updates the item, and creates a handover in one statement. Restore a fresh pending claim/item before each run.
- W5: each run requires an approved claim and a `SCHEDULED` handover. Restore that state before each run.
- W6: reset the notification to `is_read = FALSE` before each run.
- W7: each run requires a pending claim and item in `CLAIM_PENDING`. Restore that state before each run.

A simple transaction with `ROLLBACK` can be used for an individual write test where appropriate:

```sql
BEGIN;
EXPLAIN (ANALYZE, BUFFERS)
INSERT INTO ...;
ROLLBACK;
```

For a workflow query that depends on pre-existing state, create/reset the fixture before beginning the measured statement. Do not accidentally commit benchmark changes to your working dataset.

## 5. Calculate and report

For every query:

`Average (ms) = (Run 1 + Run 2 + Run 3) / 3`

Use the `Execution Time` line, not planning time. Record all environment details and retain the full plans. Discuss observed plans and results; do not make unsupported claims about performance.

## 6. Important limitations

- The SQL uses psql variables and is intended to be run with `psql`; it is not directly paste-ready for every GUI client without replacing the placeholders.
- The schema is a coursework design proposal. Confirm business rules and faculty requirements before final submission.
- No timings are supplied because none have been measured yet.


## 7. Keep timing methods distinct

The preliminary values currently recorded in `05_query_timings.md` were collected with `\\timing` in `psql`. They are elapsed statement times and must not be labelled as `EXPLAIN (ANALYZE, BUFFERS)` execution times. For the formal plan-based benchmark, run the exact current query with `EXPLAIN (ANALYZE, BUFFERS)`, record its `Execution Time`, and save the plan. Do not mix the two measurement methods in one table without explicitly identifying the method.
