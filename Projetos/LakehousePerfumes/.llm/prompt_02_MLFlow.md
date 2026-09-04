# Prompt 2 · O modelo e o MLflow

**Slides 23 a 37 · ~29 minutos · 2º deploy da noite**

> Todas as queries deste passo, prontas para colar: [`QUERIES.md`](QUERIES.md)

## O que este prompt faz

Mede as respostas da sala **antes** de treinar, treina, registra o modelo no
Unity Catalog e dá nota para os 3.000 clientes. Três `assert` quebram a tarefa
se o modelo não se pagar.

No fim existe `gold.score_propensao` — cada cliente com sua nota — e o modelo
`gold.propensao_compra` no catálogo, ao lado das tabelas.

> **É o prompt do momento da noite.** O baseline mora aqui. Não entregue antes.

---

## 1 · Antes de colar (3 min)

**Pergunte para a sala, e escreva as respostas no quadro:**

> *"Sem modelo nenhum. Você tem 200 ligações e 3.000 clientes.
> Qual coluna você ordena?"*

Vem sempre **"quem parou de comprar"** e **"quem compra mais"**. Anote as duas
— daqui a dez minutos elas viram número na frente de todo mundo.

Depois relembre a régua, que saiu do prompt 1:

```sql
SELECT ROUND(100 * AVG(comprou_em_7d), 1) AS taxa_base_pct
FROM lakehouse_rotaperfume.gold.features_treino;
```

**~10,1% — vinte de cada duzentas.**

---

## 2 · Colar o prompt

Bloco **## O prompt** de
[`../prd/prompt-02-modelo.md`](../prd/prompt-02-modelo.md).

Este é o mais longo dos três. Deixe rodar: são vários minutos, e é justamente
onde ficam os melhores slides.

---

## 3 · Enquanto ele trabalha (15 min de fala)

Slides **24 a 37**, nesta ordem:

- **24** — o problema escrito em uma frase
- **25** — o algoritmo tem três linhas
- **26** — como a árvore aprende
- **27** — por que árvore, e não Poisson *(pule se estiver atrasado)*
- **28** — **o que é AUC**, com a régua da sala
- **29** — vazamento de dado
- **30** — um dado errado quebra, um modelo ruim funciona
- **32 a 37** — o que é MLflow, a anatomia de um run, por que aqui

---

## 4 · Rode só a tarefa (35s, não 3m30)

```bash
cd aulas/aula-02-engenharia-de-dados/rotaperfume
bash scripts/rodar-tarefa.sh <perfil> ml_modelo
```

O job completo fica para o fim da noite, quando você vai mostrar o DAG inteiro.

---

## 5 · Quando terminar: onde clicar

- [ ] **Leia a saída da tarefa em voz alta** — o baseline está impresso lá.
      É o momento da noite: *"ligue para quem comprou recentemente" deu
      **0,3522**, muito pior que jogar moeda.*
- [ ] E o número do diretor: **86 dos 200 compram, contra 20 às cegas —
      4,25×**
- [ ] **Catalog** → `lakehouse_rotaperfume` → `gold` → **Models**
      → `propensao_compra`, com a versão 1 e o alias `@prod`
      (na CLI, só `model-versions get-by-alias` mostra o alias — `list` não)
- [ ] Clique no modelo → mostre que ele fica **do lado das tabelas**,
      no mesmo catálogo, com o mesmo GRANT
- [ ] **Experiments** (menu da esquerda) → o run do treino
      → aba **Metrics**: `auc`, `lift_top200`, `acertos_top200`
- [ ] **Jobs & Pipelines** → o DAG agora tem `ml_modelo` depois de `ml_features`

---

## 6 · A query que prova

```sql
-- 1. A RESPOSTA DO DIRETOR, em uma linha
SELECT ROUND(100 * taxa_base, 1) AS pct_se_ligasse_aleatorio,
       acertos_top200            AS dos_200_quantos_compram,
       ROUND(lift_top200, 2)     AS quantas_vezes_melhor,
       ROUND(auc, 4)             AS auc
FROM lakehouse_rotaperfume.gold.modelo_metricas
ORDER BY _treinado_em DESC LIMIT 1;

-- 2. A PROVA QUE O COMERCIAL ENTENDE (sem falar em AUC)
SELECT faixa, clientes, compraram,
       ROUND(100 * taxa_de_compra, 1) AS pct_que_comprou
FROM lakehouse_rotaperfume.gold.calibragem_holdout
ORDER BY score_medio;
```

Na segunda, a taxa **tem que subir** de Fria para Muito quente. Se sobe, o
score ordena — e ninguém precisa saber o que é curva ROC para conferir.

---

## 7 · Quebre um teste de propósito (2 min, vale a noite)

Mostre a linha no código:

```python
assert auc < 0.99, "bom demais é vazamento, não competência"
```

> *"Este job quebra se o resultado ficar bom demais. É a única defesa que
> funciona contra vazamento, porque vazamento não chega com erro — chega com
> elogio."*

Se sobrar tempo, rode o notebook
[`../notebooks/02-o-vazamento-de-dado.py`](../notebooks/02-o-vazamento-de-dado.py):
dois modelos idênticos, um com o filtro de data e outro sem. **~0,867 contra
~0,9998.**

---

## 8 · Emenda para o próximo

> *"Cliente 1847, score 0,8412. O vendedor não faz nada com isso. Falta o
> último metro."*

---

## Se der errado

| O que aparece | O que fazer |
|---|---|
| `BAD_REQUEST: For input string: "None"` | falta `WorkspaceClient().workspace.mkdirs(...)` antes do `set_experiment` |
| `AttributeError: __sklearn_tags__` | virou XGBoost em algum lugar — peça `HistGradientBoostingClassifier` |
| `InvalidVersion: '18.x-aarch64-photon-scala2'` | usou `spark_udf` — peça `mlflow.sklearn.load_model` + pandas |
| O `score` só tem 0 e 1 | usou `predict` — peça `predict_proba()[:, 1]` |
| `Object of type Decimal is not JSON serializable` | volta ao prompt 1: `cast("double")` nas features |
| **O assert do baseline quebrou o job** | **não conserte ao vivo.** É a aula acontecendo — leia a mensagem e discuta |