-- Silver: pedidos tipados, com cancelamento e valor líquido explícitos.

CREATE OR REPLACE TABLE lakehouse_rotaperfume.silver.pedidos
COMMENT 'Silver — pedidos tipados; valor_liquido é zero quando cancelado, valor_total caso contrário.'
AS
WITH convertido AS (
  SELECT
    *,
    coalesce(try_to_date(data_pedido), try_to_date(data_pedido, 'dd/MM/yyyy')) AS data_pedido_convertida,
    CAST(valor_total AS DECIMAL(18, 2)) AS valor_total_decimal
  FROM lakehouse_rotaperfume.bronze.pedidos
)
SELECT
  pedido_id,
  cliente_id,
  vendedor_id,
  data_pedido_convertida AS data_pedido,
  canal,
  status,
  valor_total_decimal AS valor_total,
  status = 'Cancelado' AS cancelado,
  CASE WHEN status = 'Cancelado' THEN CAST(0 AS DECIMAL(18, 2)) ELSE valor_total_decimal END AS valor_liquido,
  year(data_pedido_convertida) AS ano,
  month(data_pedido_convertida) AS mes,
  current_timestamp() AS _processado_em,
  (SELECT COUNT(*) FROM lakehouse_rotaperfume.bronze.pedidos) AS _linhas_origem
FROM convertido;

COMMENT ON COLUMN lakehouse_rotaperfume.silver.pedidos.data_pedido IS
  'Convertido de ISO e dd/MM/yyyy misturados via coalesce de dois try_to_date.';
COMMENT ON COLUMN lakehouse_rotaperfume.silver.pedidos.cancelado IS
  'Derivado de status = Cancelado.';
COMMENT ON COLUMN lakehouse_rotaperfume.silver.pedidos.valor_liquido IS
  'Zero quando cancelado, valor_total caso contrário. Pode ficar negativo legitimamente quando o pedido tem itens devolvidos — isso não é sujeira.';

ALTER TABLE lakehouse_rotaperfume.silver.pedidos
  ADD CONSTRAINT data_pedido_nao_nula CHECK (data_pedido IS NOT NULL);
ALTER TABLE lakehouse_rotaperfume.silver.pedidos
  ADD CONSTRAINT pedido_cancelado_zerado CHECK (NOT cancelado OR valor_liquido = 0);
