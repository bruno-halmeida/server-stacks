#!/usr/bin/env bash
# Gera/renova Docker Secrets para a stack blog (WordPress + MariaDB).
# Valores são gerados via openssl, enviados ao swarm pela stdin e descartados
# da memória — nunca tocam disco do host.
#
# Secrets criados:
#   blog_db_root_password_v<timestamp>   — senha root do MariaDB
#   blog_wp_db_password_v<timestamp>     — senha do usuário "wordpress" no DB
#   blog_wp_auth_key_v<timestamp>        \
#   blog_wp_secure_auth_key_v<timestamp>  |
#   blog_wp_logged_in_key_v<timestamp>    |  8 salts individuais do WordPress
#   blog_wp_nonce_key_v<timestamp>        |  (cada chave num secret próprio,
#   blog_wp_auth_salt_v<timestamp>        |   consumidos pelo WP via
#   blog_wp_secure_auth_salt_v<timestamp> |   WORDPRESS_<KEY>_FILE)
#   blog_wp_logged_in_salt_v<timestamp>   |
#   blog_wp_nonce_salt_v<timestamp>      /
#
# Uso:
#   ./bootstrap-secrets.sh            # cria apenas os que faltam
#   ./bootstrap-secrets.sh --rotate   # cria nova versão de TODOS
#
# Os secrets do Swarm são imutáveis — pra rotacionar cria-se com nome versionado
# e atualiza o blog.yml apontando para o nome novo.

set -euo pipefail

ROTATE=0
if [[ "${1:-}" == "--rotate" ]]; then
  ROTATE=1
fi

VERSION="$(date +%Y%m%d%H%M%S)"
PREFIX="blog"

create_secret() {
  local logical_name="$1"
  local value="$2"
  local versioned="${PREFIX}_${logical_name}_v${VERSION}"

  if [[ $ROTATE -eq 0 ]]; then
    local existing
    existing="$(docker secret ls --format '{{.Name}}' | grep -E "^${PREFIX}_${logical_name}_v[0-9]+$" || true)"
    if [[ -n "$existing" ]]; then
      echo "[skip] ${logical_name} já existe: $existing"
      return
    fi
  fi

  printf '%s' "$value" | docker secret create "$versioned" - >/dev/null
  echo "[ok]   criado $versioned"
}

# Senhas de DB — 48 chars hex (192 bits)
create_secret "db_root_password" "$(openssl rand -hex 24)"
create_secret "wp_db_password"   "$(openssl rand -hex 24)"

# Salts do WordPress — cada chave vira um secret próprio (64 bytes base64 = 512 bits)
for key in auth_key secure_auth_key logged_in_key nonce_key \
           auth_salt secure_auth_salt logged_in_salt nonce_salt; do
  # base64 pode conter / + = ; tudo válido dentro de string PHP
  create_secret "wp_${key}" "$(openssl rand -base64 64 | tr -d '\n')"
done

echo
echo "Secrets atuais com prefixo ${PREFIX}_:"
docker secret ls --format 'table {{.Name}}\t{{.CreatedAt}}' | grep -E "^(NAME|${PREFIX}_)" || true

echo
echo "Versão gerada: ${VERSION}"
echo "Próximo passo: atualize os names versionados no blog.yml e rode:"
echo "  docker stack deploy -c blog.yml blog"
