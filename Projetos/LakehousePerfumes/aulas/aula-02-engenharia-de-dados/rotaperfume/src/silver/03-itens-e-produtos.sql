-- Silver: produtos tipados, e itens_pedido com devolução sinalizada
-- (nunca descartada) e SKU descontinuado marcado via join com produtos.

CREATE OR REPLACE TABLE lakehouse_rotaperfume.silver.produtos
COMMENT 'Silver — produtos tipados.'
AS
SELECT
  sku,
  descricao,
  categoria,
  marca,
  nota_olfativa,
  CAST(preco_tabela AS DECIMAL(18, 2)) AS preco_tabela,
  CAST(custo_unitario AS DECIMAL(18, 2)) AS custo_unitario,
  unidade,
  ativo = 'S' AS ativo,
  try_to_date(data_lancamento) AS data_lancamento,
  current_timestamp() AS _processado_em,
  (SELECT COUNT(*) FROM lakehouse_rotaperfume.bronze.produtos) AS _linhas_origem
FROM lakehouse_rotaperfume.bronze.produtos;

CREATE OR REPLACE TABLE lakehouse_rotaperfume.silver.itens_pedido
COMMENT 'Silver — itens de pedido; devolução (quantidade negativa) é sinalizada, nunca descartada.'
AS
SELECT
  i.item_id,
  i.pedido_id,
  i.sku,
  try_cast(i.quantidade AS INT) AS quantidade,
  abs(try_cast(i.quantidade AS INT)) AS quantidade_abs,
  try_cast(i.quantidade AS INT) < 0 AS devolucao,
  CAST(i.preco_praticado AS DECIMAL(18, 2)) AS preco_praticado,
  CAST(i.desconto_pct AS DECIMAL(9, 4)) AS desconto_pct,
  CAST(i.valor_bruto AS DECIMAL(18, 2)) AS valor_bruto,
  coalesce(NOT p.ativo, false) AS sku_descontinuado,
  current_timestamp() AS _processado_em,
  (SELECT COUNT(*) FROM lakehouse_rotaperfume.bronze.itens_pedido) AS _linhas_origem
FROM lakehouse_rotaperfume.bronze.itens_pedido i
LEFT JOIN lakehouse_rotaperfume.silver.produtos p ON p.sku = i.sku;

COMMENT ON COLUMN lakehouse_rotaperfume.silver.itens_pedido.devolucao IS
  'Quantidade negativa na origem é devolução, não erro. A linha é mantida — descartá-la infla o faturamento.';
COMMENT ON COLUMN lakehouse_rotaperfume.silver.itens_pedido.quantidade_abs IS
  'Valor absoluto da quantidade; use junto com devolucao para separar venda de devolução.';
COMMENT ON COLUMN lakehouse_rotaperfume.silver.itens_pedido.sku_descontinuado IS
  'True quando o produto do item já não está ativo em silver.produtos no momento do processamento.';

ALTER TABLE lakehouse_rotaperfume.silver.itens_pedido
  ADD CONSTRAINT quantidade_abs_positiva CHECK (quantidade_abs > 0);
