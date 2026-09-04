# Databricks notebook source
# MAGIC %md
# MAGIC # Modelo de propensão de compra + MLflow
# MAGIC Mede três baselines "na mão" (recência, valor total, atraso relativo),
# MAGIC treina um `HistGradientBoostingClassifier`, registra no Unity Catalog
# MAGIC com alias `@prod`, e pontua `gold.features_cliente`. Três `assert`
# MAGIC quebram a tarefa se o modelo não se pagar — vazamento chega com
# MAGIC elogio, não com erro, então o teste mais importante é o que desconfia
# MAGIC de um resultado bom demais.

# COMMAND ----------

dbutils.widgets.text("catalog", "lakehouse_rotaperfume")
catalog = dbutils.widgets.get("catalog")

spark.sql(f"USE CATALOG `{catalog}`")

# COMMAND ----------

from datetime import datetime, timezone

import mlflow
import pandas as pd
from databricks.sdk import WorkspaceClient
from mlflow import MlflowClient
from sklearn.ensemble import HistGradientBoostingClassifier
from sklearn.metrics import roc_auc_score
from sklearn.model_selection import train_test_split

RANDOM_STATE = 42
TEST_SIZE = 0.3
TOP_N = 200

FEATURES_NUMERICAS = [
    "recencia_dias",
    "frequencia_pedidos",
    "valor_total",
    "ticket_medio",
    "intervalo_medio_dias",
    "atraso_relativo",
    "dias_desde_primeiro_pedido",
    "dias_desde_cadastro",
    "pedidos_ultimos_90d",
    "receita_ultimos_90d",
    "participacao_receita_90d_pct",
    "categorias_distintas",
    "marcas_distintas",
    "quantidade_itens_total",
    "taxa_devolucao_pct",
    "visitas_ultimos_90d",
    "dias_desde_ultima_visita",
    "oportunidades_abertas",
]

# COMMAND ----------

treino_pd = spark.table("gold.features_treino").toPandas()

X = pd.get_dummies(treino_pd[FEATURES_NUMERICAS + ["segmento", "multicanal"]], columns=["segmento"])
y = treino_pd["comprou_em_7d"]

X_treino, X_teste, y_treino, y_teste = train_test_split(
    X, y, test_size=TEST_SIZE, random_state=RANDOM_STATE, stratify=y
)

# COMMAND ----------

# Baselines "na mão" — a régua da sala, medida ANTES do modelo. Cada uma
# usa uma única coluna do holdout como se fosse o score.
recencia_teste = treino_pd.loc[X_teste.index, "recencia_dias"]
valor_total_teste = treino_pd.loc[X_teste.index, "valor_total"]
atraso_teste = treino_pd.loc[X_teste.index, "atraso_relativo"].fillna(0)

baseline_recencia = roc_auc_score(y_teste, -recencia_teste)
baseline_valor_total = roc_auc_score(y_teste, valor_total_teste)
baseline_atraso = roc_auc_score(y_teste, atraso_teste)

# COMMAND ----------

modelo = HistGradientBoostingClassifier(random_state=RANDOM_STATE)
modelo.fit(X_treino, y_treino)
scores_teste = modelo.predict_proba(X_teste)[:, 1]

auc = roc_auc_score(y_teste, scores_teste)

taxa_base = y_teste.mean()
ordem = scores_teste.argsort()[::-1][:TOP_N]
acertos_top200 = int(y_teste.to_numpy()[ordem].sum())
lift_top200 = (acertos_top200 / TOP_N) / taxa_base

if hasattr(modelo, "feature_importances_"):
    importancias = pd.Series(modelo.feature_importances_, index=X_treino.columns)
else:
    # HistGradientBoostingClassifier não expõe feature_importances_ nativo
    # — usa permutation importance como alternativa.
    from sklearn.inspection import permutation_importance

    resultado_perm = permutation_importance(
        modelo, X_teste, y_teste, n_repeats=5, random_state=RANDOM_STATE, scoring="roc_auc"
    )
    importancias = pd.Series(resultado_perm.importances_mean, index=X_teste.columns)

feature_mais_importante = importancias.idxmax()

# COMMAND ----------

# Três asserts que quebram a tarefa se o modelo não se pagar.
# 1) confirmado no roteiro: bom demais é vazamento, não competência.
assert auc < 0.99, "bom demais é vazamento, não competência"
# 2) o modelo tem que ser claramente melhor que jogar moeda (0,5).
assert auc > 0.6, f"AUC {auc:.4f} não é melhor que jogar moeda o suficiente para ir a produção"
# 3) selecionar pelo score tem que valer mais do que selecionar aleatório.
assert lift_top200 > 1, f"lift {lift_top200:.2f} não supera selecionar clientes aleatoriamente"

# COMMAND ----------

mlflow.set_registry_uri("databricks-uc")

usuario = WorkspaceClient().current_user.me().user_name
pasta_experimentos = f"/Users/{usuario}/rotaperfume"
experimento_path = f"{pasta_experimentos}/propensao_compra"
# mkdirs cria a pasta MÃE, nunca o próprio caminho do experimento — se o
# path do experimento já existir como pasta, set_experiment quebra com
# "node ... already exists ... cannot create node of type MLFLOW_EXPERIMENT".
WorkspaceClient().workspace.mkdirs(pasta_experimentos)
mlflow.set_experiment(experimento_path)

nome_modelo_uc = f"{catalog}.gold.propensao_compra"

with mlflow.start_run(run_name="propensao_compra") as run:
    mlflow.log_param("algoritmo", "HistGradientBoostingClassifier")
    mlflow.log_param("random_state", RANDOM_STATE)
    mlflow.log_param("test_size", TEST_SIZE)
    mlflow.log_metric("auc", auc)
    mlflow.log_metric("lift_top200", lift_top200)
    mlflow.log_metric("acertos_top200", acertos_top200)
    mlflow.log_metric("taxa_base", taxa_base)
    mlflow.log_metric("baseline_recencia", baseline_recencia)
    mlflow.log_metric("baseline_valor_total", baseline_valor_total)
    mlflow.log_metric("baseline_atraso", baseline_atraso)

    info_modelo = mlflow.sklearn.log_model(
        modelo,
        artifact_path="modelo",
        input_example=X_treino.head(5),
        registered_model_name=nome_modelo_uc,
    )

versao_registrada = info_modelo.registered_model_version
MlflowClient().set_registered_model_alias(nome_modelo_uc, "prod", versao_registrada)

# COMMAND ----------

agora = datetime.now(timezone.utc)

metricas_pd = pd.DataFrame(
    [
        {
            "auc": float(auc),
            "lift_top200": float(lift_top200),
            "acertos_top200": acertos_top200,
            "taxa_base": float(taxa_base),
            "baseline_recencia": float(baseline_recencia),
            "baseline_valor_total": float(baseline_valor_total),
            "baseline_atraso": float(baseline_atraso),
            "feature_mais_importante": str(feature_mais_importante),
            "versao": str(versao_registrada),
            "_treinado_em": agora,
        }
    ]
)
spark.createDataFrame(metricas_pd).write.mode("append").option(
    "mergeSchema", "true"
).saveAsTable("gold.modelo_metricas")
spark.sql(
    "COMMENT ON TABLE gold.modelo_metricas IS "
    "'Uma linha por treino do modelo de propensão: AUC, lift, baselines e a versão registrada no Unity Catalog.'"
)

# COMMAND ----------

FAIXAS = ["Fria", "Morna", "Quente", "Muito quente"]
calibragem_pd = pd.DataFrame(
    {"score": scores_teste, "comprou_em_7d": y_teste.to_numpy()}
)
calibragem_pd["faixa"] = pd.qcut(calibragem_pd["score"], 4, labels=FAIXAS)

calibragem_resumo = (
    calibragem_pd.groupby("faixa", observed=True)
    .agg(
        clientes=("comprou_em_7d", "size"),
        compraram=("comprou_em_7d", "sum"),
        score_medio=("score", "mean"),
    )
    .reset_index()
)
calibragem_resumo["taxa_de_compra"] = calibragem_resumo["compraram"] / calibragem_resumo["clientes"]
calibragem_resumo["faixa"] = calibragem_resumo["faixa"].astype(str)

spark.createDataFrame(calibragem_resumo).write.mode("overwrite").option(
    "overwriteSchema", "true"
).saveAsTable("gold.calibragem_holdout")
spark.sql(
    "COMMENT ON TABLE gold.calibragem_holdout IS "
    "'Holdout do treino dividido em 4 faixas de score (quartis); a taxa de compra tem que subir de Fria para Muito quente — prova visual de que o score ordena, sem precisar explicar AUC.'"
)

# COMMAND ----------

# Pontuação de gold.features_cliente. Carrega via mlflow.sklearn.load_model
# + pandas — nunca spark_udf (a versão do runtime do spark_udf não bate com
# o cluster serverless).
modelo_prod = mlflow.sklearn.load_model(f"models:/{nome_modelo_uc}@prod")

cliente_pd = spark.table("gold.features_cliente").toPandas()
X_cliente = pd.get_dummies(
    cliente_pd[FEATURES_NUMERICAS + ["segmento", "multicanal"]], columns=["segmento"]
)
# Garante as mesmas colunas (mesma ordem) do treino — segmentos que não
# aparecem em features_cliente viram coluna de zeros, nunca quebram o predict.
X_cliente = X_cliente.reindex(columns=X_treino.columns, fill_value=0)

scores_cliente = modelo_prod.predict_proba(X_cliente)[:, 1]

score_pd = pd.DataFrame(
    {
        "cliente_id": cliente_pd["cliente_id"],
        "score": scores_cliente,
        "faixa": pd.qcut(scores_cliente, 4, labels=FAIXAS).astype(str),
        "_referencia": cliente_pd["_referencia"],
        "_pontuado_em": agora,
    }
)
spark.createDataFrame(score_pd).write.mode("overwrite").option(
    "overwriteSchema", "true"
).saveAsTable("gold.score_propensao")
spark.sql(
    "COMMENT ON TABLE gold.score_propensao IS "
    "'Nota de propensão de compra (0 a 1) por cliente, gerada pelo modelo gold.propensao_compra@prod sobre gold.features_cliente.'"
)
spark.sql(
    "COMMENT ON COLUMN gold.score_propensao.score IS "
    "'Probabilidade estimada de o cliente comprar nos próximos 7 dias — quanto maior, mais prioritário para contato.'"
)
spark.sql(
    "COMMENT ON COLUMN gold.score_propensao.faixa IS "
    "'Quartil do score entre os clientes pontuados nesta rodada (Fria a Muito quente) — mesma convenção de gold.calibragem_holdout.'"
)

# COMMAND ----------

print(f"AUC do modelo: {auc:.4f}")
print(f"Baseline recência:    {baseline_recencia:.4f}")
print(f"Baseline valor total: {baseline_valor_total:.4f}")
print(f"Baseline atraso:      {baseline_atraso:.4f}")
print(f"Top {TOP_N}: {acertos_top200} compradores (taxa base {taxa_base * 100:.2f}%) — lift {lift_top200:.2f}x")
print(f"Feature mais importante: {feature_mais_importante}")
print(f"Modelo registrado: {nome_modelo_uc}, versão {versao_registrada}, alias @prod")
print(f"Clientes pontuados: {len(score_pd)}")
