# Docker Secrets Configuration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Keep provider credentials out of Flutter and the Docker container environment while preserving `.env`-based local development.

**Architecture:** Pydantic settings accept direct secret values or file paths, preferring direct values and otherwise reading Docker-mounted files into `SecretStr`. Docker Compose sources secret contents from its host environment, mounts them under `/run/secrets`, and passes only non-sensitive file paths plus ordinary configuration into the container.

**Tech Stack:** Python 3.11, Pydantic Settings 2, pytest, Docker Compose, Flutter configuration audit.

## Global Constraints

- Flutter contains no provider API key, token, secret path, or provider credential setting.
- Local Python development reads ignored `.env` values through the existing Pydantic settings model.
- Docker does not use `env_file` and does not expose provider key values through container environment variables.
- Direct secret values take precedence over file-backed values.
- Missing, unreadable, or empty secret files fail without logging file contents.
- No actual credential value is added to tests, documentation, image layers, or Git.

---

### Task 1: File-backed server credentials

**Files:**
- Modify: `server/app/config.py`
- Create: `server/tests/test_config.py`

**Interfaces:**
- Consumes: existing `Settings.mimo_api_key`, `Settings.llm_api_key`, and `SecretStr` provider wiring.
- Produces: `Settings.mimo_api_key_file: Path | None`, `Settings.llm_api_key_file: Path | None`, and direct-value-first file loading.

- [ ] **Step 1: Write failing settings tests**

```python
def test_settings_load_keys_from_secret_files(tmp_path):
    mimo = tmp_path / "mimo"
    llm = tmp_path / "llm"
    mimo.write_text("mimo-file-key\n")
    llm.write_text("llm-file-key\n")
    settings = Settings(
        _env_file=None,
        mimo_api_key_file=mimo,
        llm_api_key_file=llm,
    )
    assert settings.mimo_api_key.get_secret_value() == "mimo-file-key"
    assert settings.llm_api_key.get_secret_value() == "llm-file-key"

def test_direct_key_takes_precedence_over_secret_file(tmp_path):
    secret = tmp_path / "mimo"
    secret.write_text("file-key")
    settings = Settings(
        _env_file=None,
        mimo_api_key="direct-key",
        mimo_api_key_file=secret,
    )
    assert settings.mimo_api_key.get_secret_value() == "direct-key"
```

```python
def test_missing_secret_file_is_rejected_without_content(tmp_path):
    missing = tmp_path / "missing"
    with pytest.raises(ValidationError, match="MIMO_API_KEY_FILE could not be read"):
        Settings(_env_file=None, mimo_api_key_file=missing)

def test_empty_secret_file_is_rejected(tmp_path):
    empty = tmp_path / "empty"
    empty.write_text("  \n")
    with pytest.raises(ValidationError, match="MIMO_API_KEY_FILE is empty"):
        Settings(_env_file=None, mimo_api_key_file=empty)
```

- [ ] **Step 2: Run focused tests and verify failure**

Run: `cd server && PYTHONPATH=../.python-deps:. ../.python-deps/bin/pytest tests/test_config.py -q`

Expected: FAIL because `Settings` does not accept or load `_FILE` fields.

- [ ] **Step 3: Implement direct-or-file secret resolution**

Add `Path` fields and an after-model validator. For each pair, return immediately when the direct `SecretStr` exists; otherwise read UTF-8 text from the configured path, strip whitespace, reject unreadable or empty files with a stable field-specific `ValueError`, and assign `SecretStr(value)`. Do not include file contents in exception messages.

- [ ] **Step 4: Run server regression tests**

Run: `cd server && PYTHONPATH=../.python-deps:. ../.python-deps/bin/pytest -q`

Expected: all settings and existing provider tests pass.

- [ ] **Step 5: Commit**

```bash
git add server/app/config.py server/tests/test_config.py
git commit -m "feat(server): load credentials from secret files"
```

### Task 2: Docker Secrets wiring and documentation

**Files:**
- Modify: `docker-compose.yml`
- Modify: `.env.example`
- Modify: `README.md`
- Test: repository configuration and secret scans

**Interfaces:**
- Consumes: `MIMO_API_KEY_FILE` and `LLM_API_KEY_FILE` from Task 1.
- Produces: Compose secrets `mimo_api_key` and `llm_api_key`, mounted at `/run/secrets/mimo_api_key` and `/run/secrets/llm_api_key`.

- [ ] **Step 1: Replace Compose environment injection with secrets**

Remove `env_file`. Add service environment entries for non-secret settings and the two `_FILE` paths. Add service secret grants and top-level secret definitions sourced from host environment variables:

```yaml
services:
  voice-server:
    environment:
      MIMO_API_KEY_FILE: /run/secrets/mimo_api_key
      LLM_API_KEY_FILE: /run/secrets/llm_api_key
      MIMO_BASE_URL: ${MIMO_BASE_URL:-https://token-plan-cn.xiaomimimo.com/v1}
      LLM_PROVIDER: ${LLM_PROVIDER:-openai_compatible}
      LLM_MODEL: ${LLM_MODEL:-mimo-v2.5}
      LLM_BASE_URL: ${LLM_BASE_URL:-https://token-plan-cn.xiaomimimo.com/v1}
      VOICE_HOST: ${VOICE_HOST:-0.0.0.0}
      VOICE_PORT: ${VOICE_PORT:-8000}
      LOG_LEVEL: ${LOG_LEVEL:-INFO}
    secrets:
      - mimo_api_key
      - llm_api_key

secrets:
  mimo_api_key:
    environment: MIMO_API_KEY
  llm_api_key:
    environment: LLM_API_KEY
```

List every non-secret server setting explicitly using Compose interpolation and the defaults from `.env.example`.

- [ ] **Step 2: Document local and Docker configuration paths**

Keep direct key fields in `.env.example` because Compose sources its secrets from them. Update `README.md` to state that local Python reads `.env` directly, Docker Compose converts the two values into mounted secret files, the container receives no key-valued environment variables, and Flutter only receives `VOICE_SERVER_URL`.

- [ ] **Step 3: Validate Compose structure**

Run with dummy values, never real credentials:

```bash
MIMO_API_KEY=dummy-mimo LLM_API_KEY=dummy-llm docker compose config
```

Expected: the service contains `_FILE` variables and secret mounts; it contains no `MIMO_API_KEY` or `LLM_API_KEY` environment entry.

- [ ] **Step 4: Run full verification and secret audit**

```bash
cd server && PYTHONPATH=../.python-deps:. ../.python-deps/bin/pytest -q
cd .. && git diff --check
git grep -nE 'tp-[A-Za-z0-9]{20,}' || true
rg -n 'MIMO_API_KEY|LLM_API_KEY' mobile || true
```

Expected: all tests pass, no supplied token is tracked, and Flutter has no provider key name.

- [ ] **Step 5: Commit**

```bash
git add docker-compose.yml .env.example README.md
git commit -m "feat(deploy): mount provider keys as Docker secrets"
```
