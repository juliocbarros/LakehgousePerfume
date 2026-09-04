-- Gold: a fila semanal — os 200 maiores scores, um vendedor de cada vez,
-- com motivo e sugestão em português. É a resposta literal a "quem eu ligo
-- essa semana?".
--
-- REGRA QUE IMPORTA: junta com a carteira VIGENTE antes de ordenar e
-- cortar em 200 — nunca depois. Se o corte vier antes do join, clientes
-- sem vendedor ativo (carteira órfã de vendedor desligado) somem da lista
-- e ela chega com menos de 200 linhas.
--
-- OUTRA SUJEIRA REAL: dois pares de vendedor_id compartilham o mesmo nome
-- (ex.: dois "Henrique Oliveira" distintos). Toda ferramenta e query deste
-- prompt filtra por NOME, então um nome duplicado juntaria as filas de
-- duas pessoas diferentes sob um só rótulo. Desambigua acrescentando o
-- vendedor_id ao nome só quando ele colide — os outros 40 continuam com o
-- nome puro.

CREATE OR REPLACE TABLE lakehouse_rotaperfume.gold.fila_semanal
COMMENT 'Os 200 contatos da semana, um vendedor de cada vez, só clientes com carteira vigente (vendedor ativo). É a lista que o vendedor usa na segunda de manhã.'
AS
WITH elegiveis AS (
  SELECT s.cliente_id, s.score, s.faixa, c.vendedor_id
  FROM lakehouse_rotaperfume.gold.score_propensao s
  JOIN (
    SELECT DISTINCT cliente_id, vendedor_id
    FROM lakehouse_rotaperfume.silver.carteira
    WHERE vigente
  ) c ON c.cliente_id = s.cliente_id
),
top200 AS (
  SELECT * FROM elegiveis ORDER BY score DESC LIMIT 200
),
vendedor_nome AS (
  SELECT
    vendedor_id,
    CASE
      WHEN COUNT(*) OVER (PARTITION BY nome) > 1 THEN concat(nome, ' (#', vendedor_id, ')')
      ELSE nome
    END AS vendedor
  FROM lakehouse_rotaperfume.gold.dim_vendedor
)
SELECT
  t.cliente_id,
  v.vendedor,
  ROW_NUMBER() OVER (PARTITION BY t.vendedor_id ORDER BY t.score DESC) AS ordem,
  cl.razao_social,
  cl.cidade,
  t.score,
  t.faixa,
  CASE
    WHEN f.recencia_dias > 90 THEN concat('Sem comprar há ', f.recencia_dias, ' dias — cliente em risco')
    WHEN f.atraso_relativo > 1.5 THEN concat('Atrasado ', round(f.atraso_relativo, 1), 'x em relação ao próprio ciclo de compra')
    WHEN f.pedidos_ultimos_90d = 0 THEN 'Reduziu o ritmo de compra nos últimos 90 dias'
    ELSE 'Alta propensão de compra segundo o modelo'
  END AS motivo,
  CASE
    WHEN f.recencia_dias > 90 THEN 'Ligar para reativar e entender o motivo do afastamento'
    WHEN f.atraso_relativo > 1.5 THEN 'Oferecer reposição do pedido habitual'
    WHEN f.pedidos_ultimos_90d = 0 THEN 'Apresentar novidades e reforçar contato'
    ELSE 'Aproveitar o momento para ampliar o pedido'
  END AS sugestao
FROM top200 t
JOIN vendedor_nome v ON v.vendedor_id = t.vendedor_id
JOIN lakehouse_rotaperfume.gold.dim_cliente cl ON cl.cliente_id = t.cliente_id
JOIN lakehouse_rotaperfume.gold.features_cliente f ON f.cliente_id = t.cliente_id;

COMMENT ON COLUMN lakehouse_rotaperfume.gold.fila_semanal.cliente_id IS
  'Identificador do cliente — chave para outras ferramentas (ex.: explicar_prioridade).';
COMMENT ON COLUMN lakehouse_rotaperfume.gold.fila_semanal.vendedor IS
  'Nome do vendedor responsável pelo contato. Quando dois vendedores têm o mesmo nome, o vendedor_id é anexado entre parênteses para diferenciá-los (ex.: "Henrique Oliveira (#12)").';
COMMENT ON COLUMN lakehouse_rotaperfume.gold.fila_semanal.ordem IS
  'Posição do cliente na fila daquele vendedor, do maior para o menor score.';
COMMENT ON COLUMN lakehouse_rotaperfume.gold.fila_semanal.razao_social IS
  'Cliente a contatar.';
COMMENT ON COLUMN lakehouse_rotaperfume.gold.fila_semanal.cidade IS
  'Cidade do cliente.';
COMMENT ON COLUMN lakehouse_rotaperfume.gold.fila_semanal.score IS
  'Probabilidade estimada de compra nos próximos 7 dias (gold.score_propensao).';
COMMENT ON COLUMN lakehouse_rotaperfume.gold.fila_semanal.faixa IS
  'Faixa de score (Fria a Muito quente).';
COMMENT ON COLUMN lakehouse_rotaperfume.gold.fila_semanal.motivo IS
  'Por que este cliente está na fila, em português — não é o valor técnico da feature.';
COMMENT ON COLUMN lakehouse_rotaperfume.gold.fila_semanal.sugestao IS
  'O que oferecer no contato, coerente com o motivo.';

-- As quatro ferramentas que o agente consulta. Ele não inventa número,
-- ele chama uma função e lê o resultado. Parâmetros com prefixo p_ para
-- nunca colidir com o nome de uma coluna (CREATE FUNCTION falha com
-- "coluna ambígua" quando o parâmetro tem o mesmo nome de uma coluna).

CREATE OR REPLACE FUNCTION lakehouse_rotaperfume.gold.priorizar_carteira(
  p_vendedor STRING COMMENT 'Nome do vendedor, exatamente como aparece em gold.dim_vendedor.',
  p_n INT COMMENT 'Quantos contatos retornar, do maior score para o menor.'
)
RETURNS TABLE (ordem INT, razao_social STRING, cidade STRING, score DOUBLE, faixa STRING, motivo STRING, sugestao STRING)
COMMENT 'Os top N contatos da fila semanal de UM vendedor, na ordem que ele deve ligar. Use quando o vendedor perguntar "quem eu ligo essa semana" ou "minha fila".'
RETURN
  SELECT ordem, razao_social, cidade, score, faixa, motivo, sugestao
  FROM lakehouse_rotaperfume.gold.fila_semanal
  WHERE vendedor = p_vendedor AND ordem <= p_n
  ORDER BY ordem;

CREATE OR REPLACE FUNCTION lakehouse_rotaperfume.gold.explicar_prioridade(
  p_cliente_id STRING COMMENT 'Identificador do cliente (gold.dim_cliente.cliente_id).'
)
RETURNS TABLE (
  razao_social STRING, score DOUBLE, faixa STRING, motivo STRING, sugestao STRING,
  recencia_dias INT, atraso_relativo DOUBLE
)
COMMENT 'Explica por que um cliente específico está (ou não) na fila semanal, com as duas features que mais pesam na decisão. Use quando perguntarem "por que esse cliente está no topo da minha lista?".'
RETURN
  SELECT
    cl.razao_social,
    s.score,
    s.faixa,
    fs.motivo,
    fs.sugestao,
    f.recencia_dias,
    f.atraso_relativo
  FROM lakehouse_rotaperfume.gold.score_propensao s
  JOIN lakehouse_rotaperfume.gold.dim_cliente cl ON cl.cliente_id = s.cliente_id
  JOIN lakehouse_rotaperfume.gold.features_cliente f ON f.cliente_id = s.cliente_id
  LEFT JOIN lakehouse_rotaperfume.gold.fila_semanal fs ON fs.cliente_id = s.cliente_id
  WHERE s.cliente_id = p_cliente_id;

CREATE OR REPLACE FUNCTION lakehouse_rotaperfume.gold.resumo_vendedor(
  p_vendedor STRING COMMENT 'Nome do vendedor, exatamente como aparece em gold.dim_vendedor.'
)
RETURNS TABLE (contatos BIGINT, nota_media DOUBLE, faixa_mais_comum STRING)
COMMENT 'Quantos contatos um vendedor tem na fila semanal, a nota média deles e a faixa de score mais comum. Use para responder "como está minha semana?" antes de entrar nos detalhes de cada cliente.'
RETURN
  SELECT
    COUNT(*) AS contatos,
    ROUND(AVG(score), 2) AS nota_media,
    mode(faixa) AS faixa_mais_comum
  FROM lakehouse_rotaperfume.gold.fila_semanal
  WHERE vendedor = p_vendedor;

CREATE OR REPLACE FUNCTION lakehouse_rotaperfume.gold.buscar_cliente(
  p_termo STRING COMMENT 'Trecho do nome do cliente (razão social) ou da cidade, para localizar o cliente quando não se sabe o cliente_id.'
)
RETURNS TABLE (cliente_id STRING, razao_social STRING, cidade STRING, segmento STRING)
COMMENT 'Busca clientes pelo nome ou cidade quando o vendedor descreve o cliente em vez de dar o ID. Use antes de explicar_prioridade quando só houver um nome.'
RETURN
  SELECT cliente_id, razao_social, cidade, segmento
  FROM lakehouse_rotaperfume.gold.dim_cliente
  WHERE razao_social ILIKE concat('%', p_termo, '%')
     OR cidade ILIKE concat('%', p_termo, '%')
  LIMIT 20;
