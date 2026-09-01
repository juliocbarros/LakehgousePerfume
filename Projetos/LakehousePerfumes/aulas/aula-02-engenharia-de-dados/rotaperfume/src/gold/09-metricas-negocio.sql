-- Gold: views nomeadas como uma pessoa de negócio nomearia — em português,
-- sem prefixo técnico. O COMMENT de cada view é a PERGUNTA que ela
-- responde, não uma descrição da estrutura: é isso que o Genie lê para
-- escolher onde procurar.

CREATE OR REPLACE VIEW lakehouse_rotaperfume.gold.receita_mensal (
  ano COMMENT 'Ano do mês.',
  mes COMMENT 'Mês (1-12).',
  receita COMMENT 'Receita líquida do mês (inclui devolução negativa).',
  margem COMMENT 'Margem do mês (receita menos custo do produto).',
  pedidos COMMENT 'Número de pedidos distintos no mês.',
  mes_pico_setor COMMENT 'True para abril, junho e outubro — meses de pico de venda do setor de perfumaria. Dezembro/janeiro são vale ESPERADO, não queda.'
)
COMMENT 'Responde: como a receita e a margem evoluíram mês a mês, e em quais meses o setor tem pico sazonal?'
AS
WITH agregado AS (
  SELECT ano, mes,
    SUM(receita) AS receita,
    SUM(margem) AS margem,
    COUNT(DISTINCT pedido_id) AS pedidos
  FROM lakehouse_rotaperfume.gold.fato_vendas
  GROUP BY ano, mes
),
calendario AS (
  SELECT DISTINCT ano, mes, mes_pico_setor
  FROM lakehouse_rotaperfume.gold.dim_calendario
)
SELECT a.ano, a.mes, a.receita, a.margem, a.pedidos, c.mes_pico_setor
FROM agregado a
JOIN calendario c ON c.ano = a.ano AND c.mes = a.mes;

CREATE OR REPLACE VIEW lakehouse_rotaperfume.gold.ranking_marcas (
  marca COMMENT 'Marca do produto.',
  receita COMMENT 'Receita líquida acumulada da marca.',
  margem_pct COMMENT 'Margem da marca como percentual da sua própria receita.',
  participacao_pct COMMENT 'Fatia da marca na receita total de todas as marcas.'
)
COMMENT 'Responde: quais marcas mais vendem, qual a margem de cada uma, e qual fatia da receita total cada marca representa?'
AS
WITH por_marca AS (
  SELECT marca, SUM(receita) AS receita, SUM(margem) AS margem
  FROM lakehouse_rotaperfume.gold.fato_vendas
  GROUP BY marca
)
SELECT
  marca,
  receita,
  ROUND(100 * margem / receita, 1) AS margem_pct,
  ROUND(100 * receita / SUM(receita) OVER (), 1) AS participacao_pct
FROM por_marca;

CREATE OR REPLACE VIEW lakehouse_rotaperfume.gold.margem_por_categoria (
  categoria COMMENT 'Categoria do produto.',
  receita COMMENT 'Receita líquida acumulada da categoria.',
  margem COMMENT 'Margem acumulada da categoria (receita menos custo).',
  margem_pct COMMENT 'Margem da categoria como percentual da sua receita — a categoria de maior receita nem sempre é a de maior margem.'
)
COMMENT 'Responde: qual categoria vende mais, e qual categoria realmente dá lucro?'
AS
SELECT
  categoria,
  SUM(receita) AS receita,
  SUM(margem) AS margem,
  ROUND(100 * SUM(margem) / SUM(receita), 1) AS margem_pct
FROM lakehouse_rotaperfume.gold.fato_vendas
GROUP BY categoria;

CREATE OR REPLACE VIEW lakehouse_rotaperfume.gold.clientes_em_risco (
  cliente_id COMMENT 'Identificador do cliente.',
  razao_social COMMENT 'Razão social do cliente.',
  segmento COMMENT 'Segmento comercial do cliente.',
  cidade COMMENT 'Cidade do cliente.',
  dias_sem_comprar COMMENT 'Dias desde a última compra efetivada (não cancelada). Cliente é considerado em risco (churn) acima de 90 dias.',
  receita_mensal_historica COMMENT 'Receita média por mês enquanto o cliente esteve ativo (receita acumulada dividida pelos meses entre o primeiro e o último pedido) — aproximação do quanto a empresa deixa de faturar por mês com esse cliente parado.'
)
COMMENT 'Responde: quais clientes pararam de comprar (mais de 90 dias sem pedido) e quanta receita mensal a gente está deixando de fazer com cada um?'
AS
SELECT
  cliente_id,
  razao_social,
  segmento,
  cidade,
  dias_sem_comprar,
  ROUND(receita_acumulada / GREATEST(1, MONTHS_BETWEEN(data_ultimo_pedido, data_primeiro_pedido)), 2) AS receita_mensal_historica
FROM lakehouse_rotaperfume.gold.dim_cliente
WHERE dias_sem_comprar > 90;

CREATE OR REPLACE VIEW lakehouse_rotaperfume.gold.efeito_lancamento (
  sku COMMENT 'SKU do produto.',
  descricao COMMENT 'Descrição do produto.',
  data_lancamento COMMENT 'Data de lançamento do produto no catálogo.',
  receita_120_dias_lancamento COMMENT 'Receita do SKU nos 120 dias corridos após o lançamento.',
  receita_resto_periodo COMMENT 'Receita do SKU do dia 121 após o lançamento até o fim do período disponível.',
  receita_media_diaria_lancamento COMMENT 'Receita média por dia nos primeiros 120 dias após o lançamento.',
  receita_media_diaria_resto COMMENT 'Receita média por dia no restante da vida do SKU — compare com receita_media_diaria_lancamento para medir o efeito lançamento.'
)
COMMENT 'Responde: um lançamento de produto vende mais forte nos primeiros 120 dias do que no resto da vida do SKU?'
AS
WITH janela AS (
  SELECT
    f.sku,
    p.data_lancamento,
    SUM(f.receita) FILTER (WHERE f.data_pedido < date_add(p.data_lancamento, 120)) AS receita_120_dias_lancamento,
    SUM(f.receita) FILTER (WHERE f.data_pedido >= date_add(p.data_lancamento, 120)) AS receita_resto_periodo,
    DATEDIFF(LEAST(current_date(), date_add(p.data_lancamento, 120)), p.data_lancamento) AS dias_janela_lancamento,
    DATEDIFF(current_date(), date_add(p.data_lancamento, 120)) AS dias_resto
  FROM lakehouse_rotaperfume.gold.fato_vendas f
  JOIN lakehouse_rotaperfume.gold.dim_produto p ON p.sku = f.sku
  WHERE p.data_lancamento IS NOT NULL
  GROUP BY f.sku, p.data_lancamento
)
SELECT
  j.sku,
  p.descricao,
  j.data_lancamento,
  j.receita_120_dias_lancamento,
  j.receita_resto_periodo,
  ROUND(j.receita_120_dias_lancamento / NULLIF(j.dias_janela_lancamento, 0), 2) AS receita_media_diaria_lancamento,
  ROUND(j.receita_resto_periodo / NULLIF(j.dias_resto, 0), 2) AS receita_media_diaria_resto
FROM janela j
JOIN lakehouse_rotaperfume.gold.dim_produto p ON p.sku = j.sku;

CREATE OR REPLACE VIEW lakehouse_rotaperfume.gold.ruptura_por_marca (
  marca COMMENT 'Marca do produto.',
  snapshots COMMENT 'Total de snapshots de estoque observados para SKUs dessa marca.',
  snapshots_em_ruptura COMMENT 'Snapshots em que o saldo estava zerado (ruptura).',
  ruptura_pct COMMENT 'Percentual de snapshots em ruptura — quanto maior, mais a marca fica sem estoque.'
)
COMMENT 'Responde: quais marcas ficam sem estoque com mais frequência?'
AS
SELECT
  p.marca,
  COUNT(*) AS snapshots,
  COUNT(*) FILTER (WHERE e.ruptura) AS snapshots_em_ruptura,
  ROUND(100.0 * COUNT(*) FILTER (WHERE e.ruptura) / COUNT(*), 1) AS ruptura_pct
FROM lakehouse_rotaperfume.silver.estoque e
JOIN lakehouse_rotaperfume.gold.dim_produto p ON p.sku = e.sku
GROUP BY p.marca;
