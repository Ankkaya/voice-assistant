#!/usr/bin/env bash
set -Eeuo pipefail

umask 077

readonly expected_image_pattern='^ghcr\.io/ankkaya/voice-assistant-server@sha256:[0-9a-f]{64}$'
readonly script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly project_dir="$(dirname -- "$script_dir")"
readonly compose_file="$script_dir/compose.prod.yml"
readonly image_env="$script_dir/image.env"
readonly previous_env="$script_dir/image.previous.env"
readonly project_env="$project_dir/.env"

usage() {
  echo "Usage: $0 ghcr.io/ankkaya/voice-assistant-server@sha256:<64 hex characters>" >&2
}

if [[ $# -ne 1 ]]; then
  usage
  exit 2
fi

readonly image_ref="$1"
if [[ ! "$image_ref" =~ $expected_image_pattern ]]; then
  echo "Refusing invalid or mutable image reference: $image_ref" >&2
  usage
  exit 2
fi

if [[ ! -s "$project_env" ]]; then
  echo "Missing server environment file: $project_env" >&2
  exit 1
fi

if [[ ! -s "$compose_file" ]]; then
  echo "Missing production Compose file: $compose_file" >&2
  exit 1
fi

read_image_ref() {
  local file="$1"
  [[ -s "$file" ]] || return 0
  sed -n 's/^VOICE_SERVER_IMAGE=//p' "$file" | tail -n 1
}

write_image_ref() {
  local ref="$1"
  local target="$2"
  local temporary
  temporary="$(mktemp "$script_dir/.image.XXXXXX")"
  printf 'VOICE_SERVER_IMAGE=%s\n' "$ref" > "$temporary"
  chmod 600 "$temporary"
  mv -f -- "$temporary" "$target"
}

compose() {
  docker compose \
    --env-file "$project_env" \
    --env-file "$image_env" \
    --file "$compose_file" \
    "$@"
}

wait_until_ready() {
  local attempt
  for attempt in $(seq 1 18); do
    if curl --fail --silent --show-error --max-time 5 \
      http://127.0.0.1:8000/health >/dev/null \
      && curl --fail --silent --show-error --max-time 5 \
        http://127.0.0.1:8000/ready >/dev/null; then
      return 0
    fi
    sleep 5
  done
  return 1
}

rollback() {
  local previous_ref="$1"
  echo "Deployment failed for $image_ref" >&2
  compose logs --no-color --tail 100 voice-server >&2 || true

  if [[ -z "$previous_ref" ]]; then
    echo "No previous image is available for rollback" >&2
    compose rm --stop --force voice-server >/dev/null 2>&1 || true
    rm -f -- "$image_env"
    return 1
  fi

  echo "Rolling back to $previous_ref" >&2
  write_image_ref "$previous_ref" "$image_env"
  compose pull voice-server
  compose up --detach --remove-orphans --wait --wait-timeout 90 voice-server
  wait_until_ready
}

previous_ref="$(read_image_ref "$image_env")"
if [[ -n "$previous_ref" ]]; then
  write_image_ref "$previous_ref" "$previous_env"
fi

write_image_ref "$image_ref" "$image_env"

if ! compose pull voice-server; then
  rollback "$previous_ref"
  exit 1
fi

if ! compose up --detach --remove-orphans --wait --wait-timeout 90 voice-server; then
  rollback "$previous_ref"
  exit 1
fi

if ! wait_until_ready; then
  rollback "$previous_ref"
  exit 1
fi

echo "Deployed $image_ref"
compose ps voice-server
