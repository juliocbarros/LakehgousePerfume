-- Gold: auditoria de metadado. Metadado faltando é BUG, não pendência de
-- documentação — a partir desta entrega tem um agente (Genie) lendo esse
-- COMMENT para decidir qual coluna usar.

CREATE OR REPLACE TEMPORARY VIEW _objetos_sem_comentario AS
SELECT table_name, table_type
FROM lakehouse_rotaperfume.information_schema.tables
WHERE table_schema = 'gold' AND (comment IS NULL OR comment = '');

CREATE OR REPLACE TEMPORARY VIEW _colunas_sem_comentario AS
SELECT table_name, column_name
FROM lakehouse_rotaperfume.information_schema.columns
WHERE table_schema = 'gold'
  AND table_name IN (
    'fato_vendas', 'receita_mensal', 'ranking_marcas', 'margem_por_categoria',
    'clientes_em_risco', 'efeito_lancamento', 'ruptura_por_marca'
  )
  AND (comment IS NULL OR comment = '');

-- Relatório de cobertura por objeto — sempre imprime, nunca falha.
-- Serve para a conversa com quem vai consumir a gold.
SELECT
  c.table_name,
  COUNT(*) AS colunas,
  COUNT(*) FILTER (WHERE c.comment IS NOT NULL AND c.comment <> '') AS comentadas,
  ROUND(100.0 * COUNT(*) FILTER (WHERE c.comment IS NOT NULL AND c.comment <> '') / COUNT(*), 1) AS cobertura_pct
FROM lakehouse_rotaperfume.information_schema.columns c
WHERE c.table_schema = 'gold'
GROUP BY c.table_name
ORDER BY cobertura_pct, c.table_name;

-- Interrompe a tarefa (e o job) se algo estiver sem COMMENT.
SELECT
  CASE
    WHEN (SELECT COUNT(*) FROM _objetos_sem_comentario) = 0
     AND (SELECT COUNT(*) FROM _colunas_sem_comentario) = 0
      THEN 'METADADO DA GOLD 100% CUBERTO'
    ELSE raise_error(concat(
      'Metadado incompleto na gold — objetos sem COMMENT: [',
      coalesce((SELECT concat_ws(', ', collect_list(table_name)) FROM _objetos_sem_comentario), ''),
      ']; colunas sem COMMENT (fato_vendas + 6 views de negócio): [',
      coalesce((SELECT concat_ws(', ', collect_list(concat(table_name, '.', column_name))) FROM _colunas_sem_comentario), ''),
      ']'
    ))
  END AS resultado_auditoria;
