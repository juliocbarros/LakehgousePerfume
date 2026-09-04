-- Gold: três marts, um por diretoria, todos agregando sobre o MESMO fato
-- (gold.fato_vendas) — nunca recalculando receita/margem do zero. É isso
-- que garante que os três somam igual (conformado).

CREATE OR REPLACE TABLE lakehouse_rotaperfume.gold.mart_vendas_por_vendedor
COMMENT 'Grão vendedor × mês: desempenho comercial contra a meta, para a diretoria comercial.'
AS
WITH agregado AS (
  SELECT
    vendedor_id,
    ano,
    mes,
    SUM(receita) AS receita,
    SUM(margem) AS margem,
    COUNT(DISTINCT cliente_id) AS clientes_atendidos,
    COUNT(DISTINCT pedido_id) AS pedidos
  FROM lakehouse_rotaperfume.gold.fato_vendas
  GROUP BY vendedor_id, ano, mes
)
SELECT
  a.vendedor_id,
  a.ano,
  a.mes,
  a.receita,
  a.margem,
  v.meta_mensal,
  ROUND(a.receita / NULLIF(v.meta_mensal, 0), 3) AS atingimento,
  a.clientes_atendidos,
  ROUND(a.receita / NULLIF(a.pedidos, 0), 2) AS ticket_medio
FROM agregado a
JOIN lakehouse_rotaperfume.gold.dim_vendedor v ON v.vendedor_id = a.vendedor_id;

COMMENT ON COLUMN lakehouse_rotaperfume.gold.mart_vendas_por_vendedor.atingimento IS
  'receita / meta_mensal do vendedor naquele mês. 1.0 = bateu a meta exatamente.';
COMMENT ON COLUMN lakehouse_rotaperfume.gold.mart_vendas_por_vendedor.ticket_medio IS
  'receita do mês dividida pelo número de pedidos distintos (não de itens).';

CREATE OR REPLACE TABLE lakehouse_rotaperfume.gold.mart_produto_performance
COMMENT 'Grão SKU × mês: desempenho de produto e curva ABC, para a diretoria de produto.'
AS
WITH totais_sku AS (
  SELECT sku, SUM(receita) AS receita_total
  FROM lakehouse_rotaperfume.gold.fato_vendas
  GROUP BY sku
),
ranking AS (
  SELECT
    sku,
    SUM(receita_total) OVER (ORDER BY receita_total DESC ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS receita_acumulada,
    SUM(receita_total) OVER () AS receita_total_geral
  FROM totais_sku
),
classificado AS (
  SELECT
    sku,
    CASE
      WHEN receita_acumulada / receita_total_geral <= 0.80 THEN 'A'
      WHEN receita_acumulada / receita_total_geral <= 0.95 THEN 'B'
      ELSE 'C'
    END AS curva_abc
  FROM ranking
),
mensal AS (
  SELECT
    sku,
    ano,
    mes,
    SUM(receita) AS receita,
    SUM(margem) AS margem,
    SUM(quantidade) AS quantidade
  FROM lakehouse_rotaperfume.gold.fato_vendas
  GROUP BY sku, ano, mes
)
SELECT
  m.sku,
  m.ano,
  m.mes,
  m.receita,
  m.margem,
  ROUND(100 * m.margem / NULLIF(m.receita, 0), 1) AS margem_pct,
  m.quantidade,
  cl.curva_abc
FROM mensal m
JOIN classificado cl ON cl.sku = m.sku;

COMMENT ON COLUMN lakehouse_rotaperfume.gold.mart_produto_performance.curva_abc IS
  'Classificação ABC pela receita ACUMULADA do SKU no período inteiro (não por mês): A = até 80% da receita total, B = até 95%, C = o resto. Mesma classe em todos os meses do mesmo SKU.';

CREATE OR REPLACE TABLE lakehouse_rotaperfume.gold.mart_financeiro_recebimento
COMMENT 'Grão mês de vencimento: contas a receber, recebido, atraso e custo de taxa, para a diretoria financeira.'
AS
SELECT
  year(data_vencimento) AS ano,
  month(data_vencimento) AS mes,
  SUM(valor) AS valor_a_receber,
  SUM(valor) FILTER (WHERE status_pagamento IN ('Pago', 'Pago com atraso')) AS recebido,
  ROUND(AVG(datediff(data_pagamento, data_vencimento)) FILTER (WHERE status_pagamento = 'Pago com atraso'), 1) AS atraso_medio_dias,
  SUM(valor - valor_liquido) AS custo_taxa
FROM lakehouse_rotaperfume.silver.pagamentos
GROUP BY year(data_vencimento), month(data_vencimento);

COMMENT ON COLUMN lakehouse_rotaperfume.gold.mart_financeiro_recebimento.recebido IS
  'Soma de valor para pagamentos com status Pago ou Pago com atraso — dinheiro que efetivamente entrou.';
COMMENT ON COLUMN lakehouse_rotaperfume.gold.mart_financeiro_recebimento.atraso_medio_dias IS
  'Média de dias entre vencimento e pagamento, só para os pagamentos marcados Pago com atraso.';
COMMENT ON COLUMN lakehouse_rotaperfume.gold.mart_financeiro_recebimento.custo_taxa IS
  'valor cobrado menos valor líquido recebido — o custo da taxa de meio de pagamento.';
