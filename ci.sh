#!/usr/bin/env bash
# ci.sh - build, deploy, promote, rollback untuk demo-app
#   ./ci.sh pipeline               build + test -> dev -> staging
#   ./ci.sh promote staging beta   butuh approval
#   ./ci.sh promote beta live      butuh approval
#   ./ci.sh deploy <env> <tag>
#   ./ci.sh rollback <env>
#   ./ci.sh status
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p .state
LOG=.state/pipeline.log

if docker compose version >/dev/null 2>&1; then DC="docker compose"; else DC="docker-compose"; fi

log() { echo "$(date '+%F %T') $*" | tee -a "$LOG"; }
name_of() { grep APP_ENV "envs/$1.env" | cut -d= -f2; }

# check <url> <env> <versi> : health OK, env & versi sesuai
check() {
  for i in $(seq 1 15); do
    curl -sf "$1/health" | grep -q '"OK"' && break
    sleep 2
  done
  curl -sf "$1/health" | grep -q '"OK"'        || { log "GAGAL: $1/health tidak OK"; return 1; }
  curl -sf "$1/environment" | grep -q "\"$2\"" || { log "GAGAL: environment bukan $2"; return 1; }
  curl -sf "$1/version" | grep -q "\"$3\""     || { log "GAGAL: version bukan $3"; return 1; }
  log "OK: $1 env=$2 versi=$3"
}

build() {
  TAG="$(cat VERSION)-$(git rev-parse --short HEAD)"
  log "BUILD demo-app:$TAG"
  docker build -q --build-arg VERSION="$TAG" -t "demo-app:$TAG" . >/dev/null
  log "TEST image $TAG"
  docker rm -f smoke >/dev/null 2>&1 || true
  docker run -d --name smoke -e APP_ENV=test -p 127.0.0.1:8099:8000 "demo-app:$TAG" >/dev/null
  if check http://127.0.0.1:8099 test "$TAG"; then
    docker rm -f smoke >/dev/null
  else
    docker rm -f smoke >/dev/null
    log "BUILD $TAG gagal test, tidak di-deploy"
    exit 1
  fi
}

up() { IMAGE_TAG="$2" $DC -p "demo-$1" --env-file "envs/$1.env" up -d; }

# deploy <env> <tag> : deploy, cek lewat nginx, rollback otomatis kalau gagal
deploy() {
  local env=$1 tag=$2 prev
  prev=$(cat ".state/$env" 2>/dev/null || true)
  log "DEPLOY $env: ${prev:-kosong} -> $tag"
  up "$env" "$tag"
  if check "http://127.0.0.1/$env" "$(name_of "$env")" "$tag"; then
    [ "$prev" != "$tag" ] && echo "$prev" > ".state/$env.prev"
    echo "$tag" > ".state/$env"
    log "SUKSES $env = $tag"
  else
    log "GAGAL deploy $env. Cek: docker ps, docker logs demo-$(name_of "$env")"
    if [ -n "$prev" ]; then
      log "ROLLBACK otomatis $env -> $prev"
      up "$env" "$prev"
      check "http://127.0.0.1/$env" "$(name_of "$env")" "$prev" || log "ROLLBACK gagal, cek manual"
    fi
    return 1
  fi
}

# promote <dari> <ke> : image yang sama dipindah, beta & live butuh approval
promote() {
  local from=$1 to=$2 tag who ans
  case "$from-$to" in
    dev-staging|staging-beta|beta-live) ;;
    *) echo "urutan promosi: dev -> staging -> beta -> live"; exit 1 ;;
  esac
  tag=$(cat ".state/$from" 2>/dev/null || true)
  [ -n "$tag" ] || { echo "$from belum punya versi"; exit 1; }
  check "http://127.0.0.1/$from" "$(name_of "$from")" "$tag" || { log "$from tidak sehat, promosi batal"; exit 1; }

  if [ "$to" = beta ] || [ "$to" = live ]; then
    echo "== APPROVAL: promosi $tag dari $from ke $to =="
    read -rp "Nama approver: " who
    read -rp "Ketik APPROVE untuk setuju: " ans
    if [ "$ans" != "APPROVE" ]; then
      echo "$(date '+%F %T') DITOLAK $tag $from->$to oleh $who" >> .state/approvals.log
      log "PROMOSI ke $to ditolak"
      exit 1
    fi
    echo "$(date '+%F %T') DISETUJUI $tag $from->$to oleh $who" >> .state/approvals.log
  fi
  deploy "$to" "$tag"
}

# rollback <env> : kembali ke versi sebelumnya
rollback() {
  local prev
  prev=$(cat ".state/$1.prev" 2>/dev/null || true)
  [ -n "$prev" ] || { echo "$1 tidak punya versi sebelumnya"; exit 1; }
  log "ROLLBACK manual $1 -> $prev"
  deploy "$1" "$prev"
}

status() {
  for env in dev staging beta live; do
    printf '%-8s versi=%-18s sebelumnya=%-18s health=%s\n' "$env" \
      "$(cat ".state/$env" 2>/dev/null || echo -)" \
      "$(cat ".state/$env.prev" 2>/dev/null || echo -)" \
      "$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1/$env/health" || true)"
  done
}

case "${1:-}" in
  pipeline) build; deploy dev "$TAG"; promote dev staging ;;
  deploy)   deploy "${2:?env}" "${3:?tag}" ;;
  promote)  promote "${2:?dari}" "${3:?ke}" ;;
  rollback) rollback "${2:?env}" ;;
  status)   status ;;
  *)        sed -n '2,8p' "$0" ;;
esac
