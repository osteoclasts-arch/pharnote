# Pharnote Doctrine Compiler

This repository now includes a Python doctrine compiler under `src/pharnote`.

## Live DB Commands

Live inspection:

```bash
python3 -m src.pharnote.ingestion.load_problem_db --inspect
```

Live scope coverage audit:

```bash
python3 -m src.pharnote.eval.audit_scope_coverage
```

Live extraction against Supabase:

```bash
python3 -m src.pharnote.doctrine.extract_candidates --problem-backend supabase
```

End-to-end pipeline after extraction:

```bash
python3 -m src.pharnote.doctrine.normalize_candidates
python3 -m src.pharnote.doctrine.cluster_doctrines
python3 -m src.pharnote.doctrine.score_doctrines
python3 -m src.pharnote.doctrine.approval_workflow
python3 -m src.pharnote.doctrine.export_pharnote_payloads
```

Fixture mode is explicit:

```bash
python3 -m src.pharnote.doctrine.extract_candidates --problem-backend fixture
```

## Required Env Vars

Live DB mode requires one of the following setups.

Preferred full-schema inspection:

- `DATABASE_URL`
- local `psql` binary available on `PATH`

Supabase REST fallback:

- `SUPABASE_URL` or `VITE_SUPABASE_URL`
- `SUPABASE_SERVICE_ROLE_KEY` preferred

Accepted weaker REST fallback if service-role is unavailable:

- `SUPABASE_ANON_KEY` or `VITE_SUPABASE_ANON_KEY`

If none of the live DB env combinations are present, live commands fail loudly. Use `--problem-backend fixture` only when fixture mode is intentional.

## Logs

Live inspection report:

- `data/doctrine/logs/problem_db_live_inspection.json`

Schema profile used by extraction:

- `data/doctrine/logs/problem_db_schema_profile.json`
