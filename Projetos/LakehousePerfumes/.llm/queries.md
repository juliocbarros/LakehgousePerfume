# As queries da noite 3, todas num lugar só

Deixe este arquivo aberto numa aba do **SQL Editor** antes de começar. É o
plano B para qualquer tela que não carregar ao vivo.

> **Cada bloco só funciona DEPOIS do prompt correspondente.** Antes disso a
> tabela não existe, e o erro é `TABLE_OR_VIEW_NOT_FOUND` — o que é o
> comportamento certo, não um problema.

---

## ⭐ A query da noite — os 200

**Depois do prompt 3.** É a resposta literal à pergunta do diretor:

```sql
SELECT vendedor, ordem, razao_social, cidade,
       ROUND(score, 2) AS nota, faixa, motivo, sugestao
FROM   lakehouse_rotaperfume.gold.fila_semanal
ORDER  BY score DESC;
```

**200 linhas.** Se vier menos, o filtro de carteira rodou depois do `LIMIT`.

### A fila de um vendedor só

```sql
SELECT ordem AS `#`, razao_social AS cliente, cidade,
       ROUND(score, 2) AS nota, motivo, sugestao
FROM   lakehouse_rotaperfume.gold.fila_semanal
WHERE  vendedor = 'Débora Souza'      -- ← troque aqui
ORDER  BY ordem;
```

### Quem recebeu quantos contatos

```sql
SELECT vendedor, COUNT(*) AS contatos, ROUND(AVG(score), 2) AS nota_media
FROM   lakehouse_rotaperfume.gold.fila_semanal
GROUP  BY vendedor
ORDER  BY contatos DESC;
```

Deu **35 vendedores, de 1 a 12 contatos**. Quem está no topo não é o melhor
vendedor — é o que tem a carteira mais quente.

### Os seis motivos

```sql
SELECT motivo, COUNT(*) AS contatos
FROM   lakehouse_rotaperfume.gold.fila_semanal
GROUP  BY motivo ORDER BY contatos DESC;
```

### A ferramenta, chamada como o agente chamaria

```sql
SELECT * FROM lakehouse_rotaperfume.gold.priorizar_carteira('Débora Souza', 5);
```

---

## Antes de tudo — a noite 2 responde?

```sql
SELECT COUNT(*) AS linhas, ROUND(SUM(receita), 2) AS receita
FROM   lakehouse_rotaperfume.gold.fato_vendas;
```

**191.080** e **102.303.828,05**. Se não bater, não comece a noite 3.

---

## Antes do prompt 1 — o contraste que abre a noite

Dois clientes que sumiram há quase o mesmo tempo, e estão em situações opostas:

```sql
WITH ritmo AS (
  SELECT f.cliente_id, c.razao_social,
         DATEDIFF(DATE'2026-08-31', MAX(f.data_pedido)) AS recencia,
         ROUND(DATEDIFF(MAX(f.data_pedido), MIN(f.data_pedido))
           / NULLIF(COUNT(DISTINCT f.pedido_id) - 1, 0), 0) AS ciclo
  FROM lakehouse_rotaperfume.gold.fato_vendas f
  JOIN lakehouse_rotaperfume.gold.dim_cliente c USING (cliente_id)
  GROUP BY f.cliente_id, c.razao_social
  HAVING COUNT(DISTINCT f.pedido_id) >= 5),
alvo AS (SELECT * FROM ritmo WHERE recencia BETWEEN 25 AND 32)
(SELECT razao_social, recencia, ciclo, ROUND(recencia/ciclo, 1) AS atraso
   FROM alvo ORDER BY ciclo ASC  LIMIT 2)
UNION ALL
(SELECT razao_social, recencia, ciclo, ROUND(recencia/ciclo, 1)
   FROM alvo ORDER BY ciclo DESC LIMIT 2);
```

**Perfumaria Prime: 28 dias sem comprar, ciclo de 24 → atraso 1,2×.
Aroma Rosa dos Ventos: 26 dias, ciclo de 139 → atraso 0,2×.**
Mesma recência, situações opostas. Esta roda **antes** do prompt 1 — só depende
da noite 2.

---

## Depois do prompt 1 — as features

```sql
-- os dois cortes, declarados na própria tabela
SELECT '_treino' AS tabela, COUNT(*) AS clientes, MIN(_referencia) AS corte,
       MIN(recencia_dias) AS menor_recencia
FROM   lakehouse_rotaperfume.gold.features_treino
UNION ALL
SELECT '_cliente', COUNT(*), MIN(_referencia), MIN(recencia_dias)
FROM   lakehouse_rotaperfume.gold.features_cliente;
```

**2.815 e 2.816.** E `menor_recencia` **positiva** nas duas — negativa é
vazamento.

```sql
-- O NÚMERO DO QUADRO: a taxa base
SELECT COUNT(*) AS clientes, SUM(comprou_em_7d) AS compraram,
       ROUND(100 * AVG(comprou_em_7d), 2) AS taxa_base_pct
FROM   lakehouse_rotaperfume.gold.features_treino;
```

**10,12% — vinte de cada duzentas.**

```sql
-- a feature que ordena a fila
SELECT c.razao_social, f.recencia_dias, ROUND(f.intervalo_medio_dias, 0) AS ciclo,
       ROUND(f.atraso_relativo, 1) AS atraso
FROM   lakehouse_rotaperfume.gold.features_cliente f
JOIN   lakehouse_rotaperfume.gold.dim_cliente c USING (cliente_id)
WHERE  f.atraso_relativo IS NOT NULL
ORDER  BY f.atraso_relativo DESC LIMIT 10;
```

---

## Depois do prompt 2 — o modelo

```sql
-- A RESPOSTA DO DIRETOR, numa linha
SELECT ROUND(100 * taxa_base, 2) AS pct_as_cegas,
       ROUND(200 * taxa_base)    AS dos_200_as_cegas,
       acertos_top200            AS dos_200_com_modelo,
       ROUND(lift_top200, 2)     AS lift,
       ROUND(auc, 4)             AS auc,
       feature_mais_importante, versao
FROM   lakehouse_rotaperfume.gold.modelo_metricas
ORDER  BY _treinado_em DESC LIMIT 1;
```

**20 às cegas · 86 com o modelo · lift 4,25× · AUC 0,8817 · `atraso_relativo`.**

```sql
-- O BASELINE — o momento da noite
SELECT ROUND(baseline_recencia, 4)    AS quem_comprou_recente,
       ROUND(baseline_valor_total, 4) AS quem_compra_mais,
       ROUND(baseline_atraso, 4)      AS quem_esta_atrasado,
       ROUND(auc, 4)                  AS o_modelo
FROM   lakehouse_rotaperfume.gold.modelo_metricas
ORDER  BY _treinado_em DESC LIMIT 1;
```

**0,3522 · 0,6410 · 0,7842 · 0,8817.** O primeiro é muito pior que a moeda.

```sql
-- A PROVA QUE O COMERCIAL ENTENDE
SELECT faixa, clientes, compraram,
       ROUND(100 * taxa_de_compra, 1) AS pct_que_comprou
FROM   lakehouse_rotaperfume.gold.calibragem_holdout
ORDER  BY score_medio;
```

**0% → 0,6% → 8,0% → 31,8%.** Tem que subir.

O modelo não se lista em SQL — `SHOW MODELS` não existe. Na CLI:

```bash
databricks model-versions get-by-alias \
  lakehouse_rotaperfume.gold.propensao_compra prod --profile <perfil>
```

---

## Conferir que a limpeza limpou

```sql
SHOW TABLES IN lakehouse_rotaperfume.gold LIKE '*features*';
SHOW TABLES IN lakehouse_rotaperfume.gold LIKE '*fila*';
SELECT * FROM lakehouse_rotaperfume.information_schema.routines
WHERE routine_schema = 'gold';
```

Tudo vazio, e `gold.fato_vendas` ainda respondendo 191.080.