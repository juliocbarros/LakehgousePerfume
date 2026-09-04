#!/usr/bin/env bash
# Cria o catálogo lakehouse_rotaperfume via SQL, fora do bundle.
#
# POR QUE NÃO ESTÁ NO BUNDLE: quando o Default Storage do metastore está
# ligado (sem uma managed location dedicada), a API do Unity Catalog RECUSA
# criar catálogo pelo bundle:
#   Error: Metastore storage root URL does not exist.
#          Default Storage is enabled in your account. (400 INVALID_STATE)
# O comando SQL abaixo funciona porque não passa pela API de criação de
# bundle — ele só precisa de um SQL Warehouse.
#
# Uso: scripts/criar-catalogo.sh <profile>
set -euo pipefail

PROFILE="${1:?uso: scripts/criar-catalogo.sh <profile>}"

databricks experimental aitools tools query \
  "CREATE CATALOG IF NOT EXISTS lakehouse_rotaperfume" \
  --profile "$PROFILE"
