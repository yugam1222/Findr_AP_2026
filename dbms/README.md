# Findr DBMS Milestone (Version 2)

This folder contains a proposed PostgreSQL relational design for the Findr lost-and-found application.

## Files

- `01_normalization.md` — UNF, 1NF, 2NF, 3NF and optional BCNF discussion, with functional dependencies and assumptions.
- `02_er_diagram.mmd` — Mermaid ER diagram.
- `03_schema.sql` — PostgreSQL 14+ DDL, keys, checks, indexes, and integrity triggers.
- `04_queries.sql` — READ and WRITE queries with JOINs and transactional workflows expressed as single statements where appropriate.
- `05_query_timings.md` — three-run timing table; intentionally pending until measured.
- `benchmark_instructions.md` — reproducible setup and measurement procedure.
- `plans/` — save actual EXPLAIN plan outputs here.
- `benchmarks/` — optional scripts or dataset-generation notes.

## Important: proposal vs. implementation

This is a carefully revised **design draft**, not proof that the application backend has been built or that the SQL has been executed in your environment. The team must confirm the assumptions in `01_normalization.md` and test the schema/queries against the required PostgreSQL version. Do not claim that the timings are complete until actual measurements are recorded.

## Key integrity decisions

- Claims are only for FOUND reports; users cannot claim their own found reports.
- Verification questions are only attached to FOUND reports.
- The expected verification answer is stored as a password hash. The backend verifies a submitted answer before inserting a claim; the raw answer is not stored in `claims`.
- Only the finder can approve/reject claims in this version of the workflow.
- A partial unique index prevents more than one approved claim per item.
- Approval, rejection of competing pending claims, item status update, and handover creation are part of W4; completion and the item's RETURNED status are part of W5.

## Before submission

1. Compare the assumptions and deliverables with the instructor's rubric.
2. Confirm PostgreSQL is accepted for this milestone.
3. Run the schema in a fresh test database.
4. Insert representative test data and execute all queries.
5. Fix any errors found in your actual PostgreSQL version/environment.
6. Run each query three times under the same conditions; record actual timings and averages.
7. Save actual query plans in `plans/`.
8. Update the documentation to reflect any changes agreed by the team or instructor.


## Benchmark evidence status (2026-11-03)

`05_query_timings.md` contains preliminary measurements for R3–R7 collected with `psql`'s `\\timing` command. R1 is intentionally Pending because the earlier timing run used a different SELECT statement. R2 and all WRITE timings remain Pending. These measurements were taken against a small test database loaded from an earlier schema version; they do not establish that this Version 2 schema and all catalogue queries have been tested together. Re-run the schema and queries in a fresh disposable database before treating the current design as fully validated.
