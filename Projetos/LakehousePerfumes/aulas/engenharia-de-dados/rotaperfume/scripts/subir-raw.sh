#!/usr/bin/env bash
# Sobe os CSVs de dados/erp e dados/crm (raiz do repositório) para o Volume
# bronze.raw. Precisa rodar depois de `databricks bundle deploy`, já que o
# Volume só existe depois do deploy criar os schemas/volume do catálogo.
#
# Uso: scripts/subir-raw.sh <profile> [catalog]
set -euo pipefail

PROFILE="${1:?uso: scripts/subir-raw.sh <profile> [catalog]}"
CATALOG="${2:-lakehouse_rotaperfume}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
DADOS_DIR="$REPO_ROOT/dados"

if [ ! -d "$DADOS_DIR" ]; then
  echo "ERRO: $DADOS_DIR não existe. Este bundle espera dados/erp e dados/crm na raiz do repositório." >&2
  exit 1
fi

# `databricks fs cp` exige o esquema dbfs: no destino, mesmo sendo um Volume
# do Unity Catalog.
databricks fs cp --recursive --overwrite \
  "$DADOS_DIR/erp" "dbfs:/Volumes/$CATALOG/bronze/raw/erp" \
  --profile "$PROFILE"

databricks fs cp --recursive --overwrite \
  "$DADOS_DIR/crm" "dbfs:/Volumes/$CATALOG/bronze/raw/crm" \
  --profile "$PROFILE"
