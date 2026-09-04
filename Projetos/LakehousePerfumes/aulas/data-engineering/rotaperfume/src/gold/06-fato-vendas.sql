-- Gold: fato_vendas — o contrato, escrito antes do SQL.
--
-- Granularidade: uma linha por ITEM de pedido.
-- Filtro: exclui pedidos cancelados. NÃO exclui devolução.
-- Dimensões: data_pedido, ano, mes, canal, cliente_id, razao_social,
--            segmento, cidade, vendedor_id, sku, categoria, marca,
--            nota_olfativa (+ pedido_id, item_id como chaves rastreáveis).
-- Métricas: quantidade, preco_praticado, receita, custo, margem, devolucao.
-- custo  = quantidade * custo_unitario do produto.
-- margem = receita - custo.
-- Devolução entra com quantidade e receita NEGATIVAS (sinal já vem da
-- silver), com a flag devolucao — nunca é excluída. Quem quiser o bruto
-- vendido pede SUM(receita) FILTER (WHERE NOT devolucao).
-- Particionado por ano e mes.

CREATE OR REPLACE TABLE lakehouse_rotaperfume.gold.fato_vendas
PARTITIONED BY (ano, mes)
COMMENT 'Fato de vendas, grão de item de pedido. Exclui pedidos cancelados; inclui devolução com valor negativo (flag devolucao).'
AS
-- Pedidos antigos podem apontar para um cliente_id descartado na
-- deduplicação da silver (ver cliente_ids_duplicados em silver.clientes).
-- Resolve para o cliente_id que sobreviveu antes de juntar com clientes,
-- senão o JOIN direto derruba essas linhas do fato (perdeu 153 itens de
-- 36 pedidos na primeira versão desta tabela).
WITH resolucao_cliente AS (
  SELECT cliente_id AS cliente_id_atual, cliente_id AS cliente_id_original
  FROM lakehouse_rotaperfume.silver.clientes
  UNION ALL
  SELECT cliente_id AS cliente_id_atual, explode(cliente_ids_duplicados) AS cliente_id_original
  FROM lakehouse_rotaperfume.silver.clientes
  WHERE cliente_ids_duplicados IS NOT NULL
)
SELECT
  i.item_id,
  i.pedido_id,
  p.data_pedido,
  p.ano,
  p.mes,
  p.canal,
  c.cliente_id,
  c.razao_social,
  c.segmento,
  c.cidade,
  p.vendedor_id,
  pr.sku,
  pr.categoria,
  pr.marca,
  pr.nota_olfativa,
  i.quantidade,
  i.preco_praticado,
  i.quantidade * i.preco_praticado AS receita,
  i.quantidade * pr.custo_unitario AS custo,
  i.quantidade * i.preco_praticado - i.quantidade * pr.custo_unitario AS margem,
  i.devolucao
FROM lakehouse_rotaperfume.silver.itens_pedido i
JOIN lakehouse_rotaperfume.silver.pedidos p ON p.pedido_id = i.pedido_id
JOIN resolucao_cliente r ON r.cliente_id_original = p.cliente_id
JOIN lakehouse_rotaperfume.silver.clientes c ON c.cliente_id = r.cliente_id_atual
JOIN lakehouse_rotaperfume.silver.produtos pr ON pr.sku = i.sku
WHERE NOT p.cancelado;

COMMENT ON COLUMN lakehouse_rotaperfume.gold.fato_vendas.receita IS
  'quantidade * preco_praticado. Negativa quando o item é uma devolução — não filtre sem querer, ou o faturamento infla.';
COMMENT ON COLUMN lakehouse_rotaperfume.gold.fato_vendas.custo IS
  'quantidade * custo_unitario do produto no catálogo atual.';
COMMENT ON COLUMN lakehouse_rotaperfume.gold.fato_vendas.margem IS
  'Receita menos custo do produto. Não considera desconto comercial nem frete.';
COMMENT ON COLUMN lakehouse_rotaperfume.gold.fato_vendas.devolucao IS
  'True quando a linha é uma devolução (quantidade negativa na origem). A linha fica no fato; use FILTER (WHERE NOT devolucao) para o bruto vendido.';

-- Cobertura completa de COMMENT nas colunas restantes — exigida pela
-- auditoria de metadado da entrega 6 (src/gold/10-auditoria-metadado.sql).
COMMENT ON COLUMN lakehouse_rotaperfume.gold.fato_vendas.item_id IS
  'Identificador do item dentro do pedido — chave de grão da tabela.';
COMMENT ON COLUMN lakehouse_rotaperfume.gold.fato_vendas.pedido_id IS
  'Pedido ao qual este item pertence.';
COMMENT ON COLUMN lakehouse_rotaperfume.gold.fato_vendas.data_pedido IS
  'Data em que o pedido foi feito.';
COMMENT ON COLUMN lakehouse_rotaperfume.gold.fato_vendas.ano IS
  'Ano de data_pedido — coluna de partição.';
COMMENT ON COLUMN lakehouse_rotaperfume.gold.fato_vendas.mes IS
  'Mês de data_pedido — coluna de partição.';
COMMENT ON COLUMN lakehouse_rotaperfume.gold.fato_vendas.canal IS
  'Canal de venda do pedido (Visita, App, Telefone, WhatsApp).';
COMMENT ON COLUMN lakehouse_rotaperfume.gold.fato_vendas.cliente_id IS
  'Cliente do pedido. Já resolvido para o cadastro sobrevivente da deduplicação da silver.';
COMMENT ON COLUMN lakehouse_rotaperfume.gold.fato_vendas.razao_social IS
  'Razão social do cliente no momento do processamento.';
COMMENT ON COLUMN lakehouse_rotaperfume.gold.fato_vendas.segmento IS
  'Segmento comercial do cliente (ex.: Perfumaria, Farmácia, E-commerce).';
COMMENT ON COLUMN lakehouse_rotaperfume.gold.fato_vendas.cidade IS
  'Cidade do cliente.';
COMMENT ON COLUMN lakehouse_rotaperfume.gold.fato_vendas.vendedor_id IS
  'Vendedor responsável pelo pedido.';
COMMENT ON COLUMN lakehouse_rotaperfume.gold.fato_vendas.sku IS
  'SKU do produto vendido no item.';
COMMENT ON COLUMN lakehouse_rotaperfume.gold.fato_vendas.categoria IS
  'Categoria do produto (ex.: Eau de Parfum, Kit Presente).';
COMMENT ON COLUMN lakehouse_rotaperfume.gold.fato_vendas.marca IS
  'Marca do produto.';
COMMENT ON COLUMN lakehouse_rotaperfume.gold.fato_vendas.nota_olfativa IS
  'Nota olfativa predominante do produto.';
COMMENT ON COLUMN lakehouse_rotaperfume.gold.fato_vendas.quantidade IS
  'Quantidade do item, com sinal — negativa quando é devolução.';
COMMENT ON COLUMN lakehouse_rotaperfume.gold.fato_vendas.preco_praticado IS
  'Preço unitário efetivamente praticado no item.';
