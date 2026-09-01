# Databricks notebook source
# MAGIC %md
# MAGIC # Ingestão bronze — dez tabelas em um comando
# MAGIC Lê os 10 CSVs do Volume `bronze.raw`, grava cada um em Delta em
# MAGIC `bronze.{tabela}` sem nenhuma limpeza ou conversão de tipo — tudo
# MAGIC entra como STRING, de propósito. A sujeira da origem é preservada e
# MAGIC vira prova de auditoria; converter é trabalho da silver.

# COMMAND ----------

dbutils.widgets.text("catalog", "lakehouse_rotaperfume")
catalog = dbutils.widgets.get("catalog")

# COMMAND ----------

from pyspark.sql.functions import current_timestamp, lit

TABELAS = {
    "erp": ["produtos", "pedidos", "itens_pedido", "pagamentos", "estoque"],
    "crm": ["clientes", "vendedores", "carteira", "oportunidades", "visitas"],
}

volume_base = f"/Volumes/{catalog}/bronze/raw"

spark.sql(f"USE CATALOG `{catalog}`")

# COMMAND ----------


def ingerir(sistema, tabela):
    arquivo_origem = f"{tabela}.csv"
    caminho = f"{volume_base}/{sistema}/{arquivo_origem}"

    # Tudo como STRING de propósito: sem inferSchema, sem multiLine (os
    # CSVs são CRLF com header e não precisam disso).
    df = (
        spark.read.option("header", "true")
        .csv(caminho)
        .withColumn("_ingerido_em", current_timestamp())
        .withColumn("_arquivo_origem", lit(arquivo_origem))
    )

    # overwriteSchema: tabelas com esse nome podem já existir de fora do
    # bundle (ex.: criadas manualmente antes desta entrega) com um schema
    # tipado. A bronze exige STRING em tudo, então o schema é sempre
    # substituído, não mesclado.
    df.write.mode("overwrite").option("overwriteSchema", "true").saveAsTable(f"bronze.{tabela}")

    spark.sql(
        f"COMMENT ON TABLE bronze.{tabela} IS "
        f"'Bronze — cópia bruta de {sistema}/{arquivo_origem}, sem limpeza nem conversão de tipo.'"
    )

    return spark.table(f"bronze.{tabela}").count()


# COMMAND ----------

contagens = []
for sistema, tabelas in TABELAS.items():
    for tabela in tabelas:
        linhas = ingerir(sistema, tabela)
        contagens.append({"tabela": tabela, "linhas_bronze": linhas})

# COMMAND ----------

divergencias = []
resultado = []
for c in contagens:
    linhas_raw = spark.sql(
        f"SELECT linhas FROM bronze._raw_arquivos WHERE arquivo = '{c['tabela']}.csv'"
    ).collect()[0]["linhas"]

    bate = c["linhas_bronze"] == linhas_raw
    resultado.append({**c, "linhas_raw": linhas_raw, "bate": bate})
    if not bate:
        divergencias.append(c["tabela"])

# COMMAND ----------

print(f"{'tabela':<16} {'linhas_bronze':>14} {'linhas_raw':>12} {'bate':>6}")
for r in resultado:
    print(f"{r['tabela']:<16} {r['linhas_bronze']:>14} {r['linhas_raw']:>12} {str(r['bate']):>6}")

if divergencias:
    raise Exception(
        "Contagem divergente entre bronze e bronze._raw_arquivos: " + ", ".join(divergencias)
    )

print(f"\n{len(resultado)} tabelas ingeridas e conferidas com sucesso.")
