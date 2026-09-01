-- Silver: vendedores, visitas, pagamentos, carteira, oportunidades, estoque.
-- carteira e oportunidades têm decisões que não "consertam" o dado, só o
-- expõem (orfao_vendedor_desligado) ou o traduzem corretamente (etapa real
-- é 'Fechado ganho'/'Fechado perdido', nunca 'Ganha'/'Perdida').

CREATE OR REPLACE TABLE lakehouse_rotaperfume.silver.vendedores
COMMENT 'Silver — vendedores tipados.'
AS
SELECT
  vendedor_id,
  nome,
  regiao,
  uf,
  try_to_date(data_admissao) AS data_admissao,
  try_to_date(data_desligamento) AS data_desligamento,
  CAST(meta_mensal AS DECIMAL(18, 2)) AS meta_mensal,
  current_timestamp() AS _processado_em,
  (SELECT COUNT(*) FROM lakehouse_rotaperfume.bronze.vendedores) AS _linhas_origem
FROM lakehouse_rotaperfume.bronze.vendedores;

CREATE OR REPLACE TABLE lakehouse_rotaperfume.silver.visitas
COMMENT 'Silver — visitas tipadas.'
AS
SELECT
  visita_id,
  cliente_id,
  vendedor_id,
  try_to_date(data_visita) AS data_visita,
  resultado,
  try_cast(duracao_min AS INT) AS duracao_min,
  current_timestamp() AS _processado_em,
  (SELECT COUNT(*) FROM lakehouse_rotaperfume.bronze.visitas) AS _linhas_origem
FROM lakehouse_rotaperfume.bronze.visitas;

CREATE OR REPLACE TABLE lakehouse_rotaperfume.silver.pagamentos
COMMENT 'Silver — pagamentos tipados.'
AS
SELECT
  pagamento_id,
  pedido_id,
  forma_pagamento,
  try_cast(parcelas AS INT) AS parcelas,
  CAST(valor AS DECIMAL(18, 2)) AS valor,
  CAST(taxa_pct AS DECIMAL(9, 4)) AS taxa_pct,
  CAST(valor_liquido AS DECIMAL(18, 2)) AS valor_liquido,
  try_to_date(data_vencimento) AS data_vencimento,
  try_to_date(data_pagamento) AS data_pagamento,
  status_pagamento,
  current_timestamp() AS _processado_em,
  (SELECT COUNT(*) FROM lakehouse_rotaperfume.bronze.pagamentos) AS _linhas_origem
FROM lakehouse_rotaperfume.bronze.pagamentos;

CREATE OR REPLACE TABLE lakehouse_rotaperfume.silver.carteira
COMMENT 'Silver — carteira de clientes por vendedor; expõe carteiras órfãs de vendedor desligado, sem corrigi-las.'
AS
SELECT
  c.carteira_id,
  c.cliente_id,
  c.vendedor_id,
  try_to_date(c.data_inicio) AS data_inicio,
  try_to_date(c.data_fim) AS data_fim,
  c.data_fim IS NULL AND v.data_desligamento IS NULL AS vigente,
  c.data_fim IS NULL AND v.data_desligamento IS NOT NULL AS orfao_vendedor_desligado,
  current_timestamp() AS _processado_em,
  (SELECT COUNT(*) FROM lakehouse_rotaperfume.bronze.carteira) AS _linhas_origem
FROM lakehouse_rotaperfume.bronze.carteira c
LEFT JOIN lakehouse_rotaperfume.silver.vendedores v ON v.vendedor_id = c.vendedor_id;

COMMENT ON COLUMN lakehouse_rotaperfume.silver.carteira.vigente IS
  'True só quando a carteira não terminou (data_fim nula) E o vendedor não foi desligado. Respeita as duas condições.';
COMMENT ON COLUMN lakehouse_rotaperfume.silver.carteira.orfao_vendedor_desligado IS
  'Expõe o problema real: carteira ainda aberta (data_fim nula) mas o vendedor já foi desligado. Não é corrigido aqui — é decisão do gestor.';

CREATE OR REPLACE TABLE lakehouse_rotaperfume.silver.oportunidades
COMMENT 'Silver — oportunidades tipadas, com ganha/perdida derivados da etapa real de origem.'
AS
SELECT
  oportunidade_id,
  cliente_id,
  vendedor_id,
  origem,
  try_to_date(data_abertura) AS data_abertura,
  etapa,
  etapa = 'Fechado ganho' AS ganha,
  etapa = 'Fechado perdido' AS perdida,
  try_cast(probabilidade_pct AS DECIMAL(9, 4)) AS probabilidade_pct,
  CAST(valor_estimado AS DECIMAL(18, 2)) AS valor_estimado,
  try_to_date(data_fechamento) AS data_fechamento,
  try_cast(ciclo_dias AS INT) AS ciclo_dias,
  motivo_perda,
  current_timestamp() AS _processado_em,
  (SELECT COUNT(*) FROM lakehouse_rotaperfume.bronze.oportunidades) AS _linhas_origem
FROM lakehouse_rotaperfume.bronze.oportunidades;

COMMENT ON COLUMN lakehouse_rotaperfume.silver.oportunidades.ganha IS
  'Derivado de etapa = ''Fechado ganho'' — os valores reais da origem são ''Fechado ganho''/''Fechado perdido'', nunca ''Ganha''/''Perdida''.';
COMMENT ON COLUMN lakehouse_rotaperfume.silver.oportunidades.perdida IS
  'Derivado de etapa = ''Fechado perdido''.';

CREATE OR REPLACE TABLE lakehouse_rotaperfume.silver.estoque
COMMENT 'Silver — estoque tipado, com ruptura derivada do saldo.'
AS
SELECT
  try_to_date(data_snapshot) AS data_snapshot,
  sku,
  try_cast(saldo AS INT) AS saldo,
  try_cast(saldo AS INT) = 0 AS ruptura,
  current_timestamp() AS _processado_em,
  (SELECT COUNT(*) FROM lakehouse_rotaperfume.bronze.estoque) AS _linhas_origem
FROM lakehouse_rotaperfume.bronze.estoque;

COMMENT ON COLUMN lakehouse_rotaperfume.silver.estoque.ruptura IS
  'Derivado de saldo = 0, não copiado direto da bronze — mas 100% consistente com o valor original na origem.';
