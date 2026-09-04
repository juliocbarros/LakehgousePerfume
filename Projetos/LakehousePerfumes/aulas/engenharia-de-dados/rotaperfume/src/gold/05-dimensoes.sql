-- Gold: quatro dimensões conformadas. Lê SÓ da silver, nunca da bronze.

CREATE OR REPLACE TABLE lakehouse_rotaperfume.gold.dim_cliente
COMMENT 'Uma linha por cliente: perfil, histórico de compra e recência.'
AS
-- Pedidos antigos podem apontar para um cliente_id descartado na
-- deduplicação da silver (ver cliente_ids_duplicados em silver.clientes).
-- Resolve para o cliente_id que sobreviveu antes de agregar, senão os
-- pedidos desses clientes somem da dimensão.
WITH resolucao_cliente AS (
  SELECT cliente_id AS cliente_id_atual, cliente_id AS cliente_id_original
  FROM lakehouse_rotaperfume.silver.clientes
  UNION ALL
  SELECT cliente_id AS cliente_id_atual, explode(cliente_ids_duplicados) AS cliente_id_original
  FROM lakehouse_rotaperfume.silver.clientes
  WHERE cliente_ids_duplicados IS NOT NULL
),
pedidos_cliente AS (
  SELECT
    r.cliente_id_atual AS cliente_id,
    COUNT(*) AS total_pedidos,
    SUM(p.valor_liquido) AS receita_acumulada,
    MIN(p.data_pedido) FILTER (WHERE NOT p.cancelado) AS data_primeiro_pedido,
    MAX(p.data_pedido) FILTER (WHERE NOT p.cancelado) AS data_ultimo_pedido
  FROM lakehouse_rotaperfume.silver.pedidos p
  JOIN resolucao_cliente r ON r.cliente_id_original = p.cliente_id
  GROUP BY r.cliente_id_atual
)
SELECT
  c.cliente_id,
  c.cnpj,
  c.razao_social,
  c.segmento,
  c.cidade,
  c.uf,
  c.data_cadastro,
  pc.data_primeiro_pedido,
  pc.data_ultimo_pedido,
  coalesce(pc.total_pedidos, 0) AS total_pedidos,
  coalesce(pc.receita_acumulada, 0) AS receita_acumulada,
  datediff(current_date(), pc.data_ultimo_pedido) AS dias_sem_comprar
FROM lakehouse_rotaperfume.silver.clientes c
LEFT JOIN pedidos_cliente pc ON pc.cliente_id = c.cliente_id;

COMMENT ON COLUMN lakehouse_rotaperfume.gold.dim_cliente.total_pedidos IS
  'Conta todos os pedidos do cliente, cancelados inclusos — é contagem de interação comercial, não de receita.';
COMMENT ON COLUMN lakehouse_rotaperfume.gold.dim_cliente.data_ultimo_pedido IS
  'Data do último pedido NÃO cancelado — cancelamento não conta como compra.';
COMMENT ON COLUMN lakehouse_rotaperfume.gold.dim_cliente.dias_sem_comprar IS
  'Dias desde a última compra efetivada (não cancelada). Nulo se o cliente nunca comprou.';

CREATE OR REPLACE TABLE lakehouse_rotaperfume.gold.dim_produto
COMMENT 'Uma linha por SKU: atributos de catálogo e status comercial.'
AS
SELECT
  sku,
  descricao,
  marca,
  categoria,
  nota_olfativa,
  custo_unitario,
  preco_tabela,
  data_lancamento,
  NOT ativo AS descontinuado
FROM lakehouse_rotaperfume.silver.produtos;

COMMENT ON COLUMN lakehouse_rotaperfume.gold.dim_produto.descontinuado IS
  'True quando o produto não está mais ativo no catálogo — usado para explicar itens de pedidos antigos de SKUs que já saíram de linha.';

CREATE OR REPLACE TABLE lakehouse_rotaperfume.gold.dim_vendedor
COMMENT 'Uma linha por vendedor: time comercial e status de emprego.'
AS
SELECT
  vendedor_id,
  nome,
  regiao,
  meta_mensal,
  data_desligamento IS NULL AS ativo
FROM lakehouse_rotaperfume.silver.vendedores;

COMMENT ON COLUMN lakehouse_rotaperfume.gold.dim_vendedor.ativo IS
  'True quando o vendedor não tem data de desligamento registrada.';

CREATE OR REPLACE TABLE lakehouse_rotaperfume.gold.dim_calendario
COMMENT 'Uma linha por dia, cobrindo o período real de pedidos (calculado dinamicamente, não fixo).'
AS
WITH intervalo AS (
  SELECT MIN(data_pedido) AS inicio, MAX(data_pedido) AS fim
  FROM lakehouse_rotaperfume.silver.pedidos
)
SELECT
  d AS data,
  year(d) AS ano,
  month(d) AS mes,
  date_format(d, 'MMMM') AS nome_mes,
  quarter(d) AS trimestre,
  date_format(d, 'EEEE') AS dia_semana,
  month(d) IN (4, 6, 10) AS mes_pico_setor
FROM intervalo
LATERAL VIEW explode(sequence(inicio, fim, interval 1 day)) AS d;

COMMENT ON COLUMN lakehouse_rotaperfume.gold.dim_calendario.mes_pico_setor IS
  'Abril (Dia das Mães), junho (Namorados/festas juninas) e outubro (Dia das Crianças/pré Black Friday) são os meses de pico de venda do setor de perfumaria.';
