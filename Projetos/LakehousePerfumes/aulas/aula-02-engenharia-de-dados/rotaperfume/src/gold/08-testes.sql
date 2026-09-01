-- Gold: 9 testes de qualidade. Se qualquer um falhar, a tarefa (e o job)
-- para — teste que não quebra o job não é teste, é relatório.

CREATE OR REPLACE TEMPORARY VIEW _resultados_testes AS
SELECT
  'receita_gold_igual_silver' AS teste,
  CAST(ROUND((SELECT SUM(receita) FROM lakehouse_rotaperfume.gold.fato_vendas), 2) AS STRING) AS valor,
  CAST(ROUND((SELECT SUM(valor_liquido) FROM lakehouse_rotaperfume.silver.pedidos), 2) AS STRING) AS esperado,
  abs(
    (SELECT SUM(receita) FROM lakehouse_rotaperfume.gold.fato_vendas)
    - (SELECT SUM(valor_liquido) FROM lakehouse_rotaperfume.silver.pedidos)
  ) <= 0.01 AS passou

UNION ALL
SELECT
  'cnpj_unico_silver_clientes',
  CAST((SELECT COUNT(*) - COUNT(DISTINCT cnpj) FROM lakehouse_rotaperfume.silver.clientes) AS STRING),
  '0',
  (SELECT COUNT(*) - COUNT(DISTINCT cnpj) FROM lakehouse_rotaperfume.silver.clientes) = 0

UNION ALL
SELECT
  'data_pedido_nao_nula',
  CAST((SELECT COUNT(*) FROM lakehouse_rotaperfume.silver.pedidos WHERE data_pedido IS NULL) AS STRING),
  '0',
  (SELECT COUNT(*) FROM lakehouse_rotaperfume.silver.pedidos WHERE data_pedido IS NULL) = 0

UNION ALL
SELECT
  'receita_negativa_so_devolucao',
  CAST((SELECT COUNT(*) FROM lakehouse_rotaperfume.gold.fato_vendas WHERE receita < 0 AND NOT devolucao) AS STRING),
  '0',
  (SELECT COUNT(*) FROM lakehouse_rotaperfume.gold.fato_vendas WHERE receita < 0 AND NOT devolucao) = 0

UNION ALL
SELECT
  'volume_fato_vendas',
  CAST((SELECT COUNT(*) FROM lakehouse_rotaperfume.gold.fato_vendas) AS STRING),
  'entre 140000 e 250000',
  (SELECT COUNT(*) FROM lakehouse_rotaperfume.gold.fato_vendas) BETWEEN 140000 AND 250000

UNION ALL
SELECT
  'sem_pedido_orfao',
  CAST((
    SELECT COUNT(*) FROM lakehouse_rotaperfume.gold.fato_vendas f
    LEFT ANTI JOIN lakehouse_rotaperfume.silver.pedidos p ON p.pedido_id = f.pedido_id
  ) AS STRING),
  '0',
  (
    SELECT COUNT(*) FROM lakehouse_rotaperfume.gold.fato_vendas f
    LEFT ANTI JOIN lakehouse_rotaperfume.silver.pedidos p ON p.pedido_id = f.pedido_id
  ) = 0

UNION ALL
SELECT
  'sem_cliente_orfao',
  CAST((
    SELECT COUNT(*) FROM lakehouse_rotaperfume.gold.fato_vendas f
    LEFT ANTI JOIN lakehouse_rotaperfume.silver.clientes c ON c.cliente_id = f.cliente_id
  ) AS STRING),
  '0',
  (
    SELECT COUNT(*) FROM lakehouse_rotaperfume.gold.fato_vendas f
    LEFT ANTI JOIN lakehouse_rotaperfume.silver.clientes c ON c.cliente_id = f.cliente_id
  ) = 0

UNION ALL
SELECT
  'mart_produto_soma_igual_fato',
  CAST(ROUND((SELECT SUM(receita) FROM lakehouse_rotaperfume.gold.mart_produto_performance), 2) AS STRING),
  CAST(ROUND((SELECT SUM(receita) FROM lakehouse_rotaperfume.gold.fato_vendas), 2) AS STRING),
  abs(
    (SELECT SUM(receita) FROM lakehouse_rotaperfume.gold.mart_produto_performance)
    - (SELECT SUM(receita) FROM lakehouse_rotaperfume.gold.fato_vendas)
  ) <= 0.01

UNION ALL
SELECT
  'cnpj_14_digitos_dim_cliente',
  CAST((SELECT COUNT(*) FROM lakehouse_rotaperfume.gold.dim_cliente WHERE length(cnpj) <> 14) AS STRING),
  '0',
  (SELECT COUNT(*) FROM lakehouse_rotaperfume.gold.dim_cliente WHERE length(cnpj) <> 14) = 0;

-- imprime nome, valor calculado, valor esperado e passou/falhou de cada teste
SELECT teste, valor, esperado, passou FROM _resultados_testes ORDER BY teste;

-- interrompe a tarefa (e o job) se qualquer teste falhou
SELECT
  CASE
    WHEN (SELECT COUNT(*) FROM _resultados_testes WHERE NOT passou) = 0
      THEN 'TODOS OS 9 TESTES PASSARAM'
    ELSE raise_error((
      SELECT concat('teste(s) falharam: ', concat_ws(', ', collect_list(teste)))
      FROM _resultados_testes
      WHERE NOT passou
    ))
  END AS resultado_final;
