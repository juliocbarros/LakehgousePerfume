-- Silver: clientes limpos, tipados e deduplicados por CNPJ.
-- ANSI mode está ligado neste workspace: to_date/date_trunc sobre data
-- malformada ABORTA a query em vez de virar NULL. Por isso try_to_date
-- sempre, nunca to_date.

CREATE OR REPLACE TABLE lakehouse_rotaperfume.silver.clientes
COMMENT 'Silver — clientes limpos, tipados e deduplicados por CNPJ (mantém o cadastro mais antigo).'
AS
WITH normalizado AS (
  SELECT
    cliente_id,
    lpad(regexp_replace(trim(cnpj), '[^0-9]', ''), 14, '0') AS cnpj,
    regexp_replace(initcap(razao_social), ' +', ' ') AS razao_social,
    segmento,
    cidade,
    uf,
    bairro,
    coalesce(try_to_date(data_cadastro), try_to_date(data_cadastro, 'dd/MM/yyyy')) AS data_cadastro,
    ativo = 'S' AS ativo
  FROM lakehouse_rotaperfume.bronze.clientes
),
ranqueado AS (
  SELECT *,
    row_number() OVER (PARTITION BY cnpj ORDER BY data_cadastro ASC, cliente_id ASC) AS ordem
  FROM normalizado
),
duplicados AS (
  SELECT cnpj, collect_list(cliente_id) AS todos_ids
  FROM normalizado
  GROUP BY cnpj
  HAVING COUNT(*) > 1
)
SELECT
  r.cliente_id,
  r.cnpj,
  r.razao_social,
  r.segmento,
  r.cidade,
  r.uf,
  r.bairro,
  r.data_cadastro,
  r.ativo,
  filter(d.todos_ids, id -> id <> r.cliente_id) AS cliente_ids_duplicados,
  current_timestamp() AS _processado_em,
  (SELECT COUNT(*) FROM lakehouse_rotaperfume.bronze.clientes) AS _linhas_origem
FROM ranqueado r
LEFT JOIN duplicados d ON d.cnpj = r.cnpj
WHERE r.ordem = 1;

COMMENT ON COLUMN lakehouse_rotaperfume.silver.clientes.cnpj IS
  'Normalizado para 14 dígitos: trim, regexp_replace tirando não-dígito, lpad com zero à esquerda. Nunca convertido para número.';
COMMENT ON COLUMN lakehouse_rotaperfume.silver.clientes.razao_social IS
  'Padronizado com initcap e espaço duplo colapsado.';
COMMENT ON COLUMN lakehouse_rotaperfume.silver.clientes.data_cadastro IS
  'Convertido de ISO e dd/MM/yyyy misturados via coalesce de dois try_to_date.';
COMMENT ON COLUMN lakehouse_rotaperfume.silver.clientes.cliente_ids_duplicados IS
  'IDs de cadastros duplicados do mesmo CNPJ, descartados na deduplicação; pedidos antigos podem apontar para eles.';

ALTER TABLE lakehouse_rotaperfume.silver.clientes
  ADD CONSTRAINT cnpj_14_digitos CHECK (length(cnpj) = 14);
ALTER TABLE lakehouse_rotaperfume.silver.clientes
  ADD CONSTRAINT data_cadastro_nao_nula CHECK (data_cadastro IS NOT NULL);
