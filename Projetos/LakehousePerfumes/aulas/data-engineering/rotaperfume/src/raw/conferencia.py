# Databricks notebook source
# MAGIC %md
# MAGIC # Conferência de chegada — raw
# MAGIC Confere que os 10 arquivos esperados chegaram ao Volume `bronze.raw`,
# MAGIC registra tamanho/linhas em `bronze._raw_arquivos` e falha o job se
# MAGIC algum arquivo estiver faltando ou vazio.

# COMMAND ----------

dbutils.widgets.text("catalog", "lakehouse_rotaperfume")
catalog = dbutils.widgets.get("catalog")

# COMMAND ----------

from datetime import datetime, timezone

ARQUIVOS_ESPERADOS = {
    "erp": ["produtos", "pedidos", "itens_pedido", "pagamentos", "estoque"],
    "crm": ["clientes", "vendedores", "carteira", "oportunidades", "visitas"],
}

volume_base = f"/Volumes/{catalog}/bronze/raw"

# COMMAND ----------

resultados = []
faltando = []
vazios = []

for sistema, arquivos in ARQUIVOS_ESPERADOS.items():
    for nome in arquivos:
        caminho = f"{volume_base}/{sistema}/{nome}.csv"
        try:
            info = dbutils.fs.ls(caminho)[0]
        except Exception:
            faltando.append(caminho)
            continue

        df = spark.read.option("header", "true").csv(caminho)
        linhas = df.count()
        if linhas == 0:
            vazios.append(caminho)

        resultados.append(
            {
                "sistema": sistema,
                "arquivo": f"{nome}.csv",
                "bytes": info.size,
                "linhas": linhas,
                "conferido_em": datetime.now(timezone.utc),
            }
        )

if faltando or vazios:
    detalhes = []
    if faltando:
        detalhes.append(f"faltando: {', '.join(faltando)}")
    if vazios:
        detalhes.append(f"vazios: {', '.join(vazios)}")
    raise Exception("Conferência de chegada falhou — " + "; ".join(detalhes))

# COMMAND ----------

spark.sql(f"USE CATALOG `{catalog}`")

spark.sql(
    """
    CREATE TABLE IF NOT EXISTS bronze._raw_arquivos (
        sistema STRING,
        arquivo STRING,
        bytes BIGINT,
        linhas BIGINT,
        conferido_em TIMESTAMP
    )
    COMMENT 'Registro de conferência de chegada dos arquivos raw a cada execução do pipeline.'
    """
)

df_resultados = spark.createDataFrame(resultados)
df_resultados.write.mode("append").saveAsTable("bronze._raw_arquivos")

# COMMAND ----------

print(f"{'sistema':<8} {'arquivo':<20} {'bytes':>10} {'linhas':>10}")
for r in resultados:
    print(f"{r['sistema']:<8} {r['arquivo']:<20} {r['bytes']:>10} {r['linhas']:>10}")

print(f"\n{len(resultados)} arquivos conferidos com sucesso.")
