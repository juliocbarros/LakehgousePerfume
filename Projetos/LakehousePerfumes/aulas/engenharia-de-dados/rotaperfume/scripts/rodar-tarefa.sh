#!/usr/bin/env bash
# Roda só uma tarefa do job rotaperfume_pipeline, sem esperar o pipeline
# inteiro (~35s contra ~3m30 do job completo).
#
# Uso: scripts/rodar-tarefa.sh <profile> <task_key>
set -euo pipefail

PERFIL="${1:?uso: scripts/rodar-tarefa.sh <profile> <task_key>}"
TAREFA="${2:?uso: scripts/rodar-tarefa.sh <profile> <task_key>}"

databricks bundle run rotaperfume_pipeline --target dev --profile "$PERFIL" --only "$TAREFA"
