# Docker Secrets Configuration Design

## Goal

Keep every provider credential out of Flutter and out of the container environment. Local Python development continues to read ignored `.env` values; Docker Compose turns the host-side values into mounted Docker Secrets.

## Decision

The server accepts either the existing direct variables or standard file-backed variants:

- `MIMO_API_KEY` or `MIMO_API_KEY_FILE`
- `LLM_API_KEY` or `LLM_API_KEY_FILE`

Direct variables support local development. When a direct value is absent, `Settings` reads the corresponding file, strips its trailing newline, rejects missing or empty files, and wraps the result in `SecretStr`. A direct value takes precedence when both forms are present.

Docker Compose no longer passes `.env` into the service with `env_file`. Instead, top-level Compose secrets source `MIMO_API_KEY` and `LLM_API_KEY` from the host Compose environment. The service mounts them under `/run/secrets/` and receives only the two non-sensitive `_FILE` paths. Model names, base URLs, host, port, and log level remain ordinary environment variables.

The entrypoint remains `uvicorn`; no shell wrapper exports secret contents back into the process environment.

## Security Boundaries

- Flutter contains only `VOICE_SERVER_URL`; it has no provider credential fields.
- `.env` stays ignored and is never copied into the image.
- Docker image layers contain no secret files or values.
- `docker inspect` exposes only `/run/secrets/...` paths, not secret values.
- Settings, readiness responses, provider errors, and application logs never reveal secret contents.
- Empty or unreadable secret files fail configuration without including file contents in the error.

## Verification

- Unit tests cover direct variables, file-backed values, precedence, empty files, and missing files.
- Existing provider and sensitive-logging tests continue to pass.
- `docker compose config` is validated with dummy host values when Docker Compose is available.
- Repository scans confirm that Flutter has no key names and no credential-like values are tracked.
