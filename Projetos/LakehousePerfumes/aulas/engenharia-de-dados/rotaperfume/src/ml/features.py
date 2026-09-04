# Databricks notebook source
# MAGIC %md
# MAGIC # Features de propensão de compra — `montar_features`
# MAGIC Uma linha por cliente, 20 colunas de comportamento, recalculadas a
# MAGIC partir de `gold.fato_vendas` (nunca `dim_cliente`, que agrega a base
# MAGIC inteira sem corte de data — usá-la aqui seria vazamento). Grava duas
# MAGIC tabelas: `features_treino` (corte 01/08, com `comprou_em_7d`) e
# MAGIC `features_cliente` (corte 31/08, para pontuar, sem a resposta).

# COMMAND ----------

if "dbutils" not in globals():  # pragma: no cover - apenas para ambientes locais/IDE
    class _Widgets:
        @staticmethod
        def text(name, default=None):
            return None

        @staticmethod
        def get(name, default=None):
            return default

    class _Dbutils:
        widgets = _Widgets()

    dbutils = _Dbutils()


dbutils.widgets.text("catalog", "lakehouse_rotaperfume")
catalog = dbutils.widgets.get("catalog") or "lakehouse_rotaperfume"

from pyspark.sql import SparkSession  # type: ignore[reportMissingImports]

spark = SparkSession.getActiveSession() or SparkSession.builder.getOrCreate()
spark.sql(f"USE CATALOG `{catalog}`")

# COMMAND ----------

from pyspark.sql import functions as F  # type: ignore[reportMissingImports]

JANELA_RECENTE_DIAS = 90
JANELA_ALVO_DIAS = 7

ETAPAS_FECHADAS = ["Fechado ganho", "Fechado perdido"]

COLUNAS_DOUBLE = [
    "valor_total",
    "ticket_medio",
    "intervalo_medio_dias",
    "atraso_relativo",
    "receita_ultimos_90d",
    "participacao_receita_90d_pct",
    "taxa_devolucao_pct",
]


def montar_features(referencia_str, com_alvo):
    referencia = F.lit(referencia_str).cast("date")

    fato = spark.table("gold.fato_vendas").filter(F.col("data_pedido") <= referencia)

    agregados = fato.groupBy("cliente_id").agg(
        F.max("data_pedido").alias("_ultimo_pedido"),
        F.min("data_pedido").alias("_primeiro_pedido"),
        F.countDistinct("pedido_id").alias("frequencia_pedidos"),
        F.sum("receita").alias("valor_total"),
        F.countDistinct("categoria").alias("categorias_distintas"),
        F.countDistinct("marca").alias("marcas_distintas"),
        F.countDistinct("canal").alias("canais_distintos"),
        F.sum(F.when(~F.col("devolucao"), F.col("quantidade")).otherwise(0)).alias(
            "quantidade_itens_total"
        ),
        F.count(F.lit(1)).alias("_itens_totais"),
        F.sum(F.when(F.col("devolucao"), 1).otherwise(0)).alias("_itens_devolvidos"),
    )

    recente = (
        fato.filter(F.col("data_pedido") > F.date_sub(referencia, JANELA_RECENTE_DIAS))
        .groupBy("cliente_id")
        .agg(
            F.countDistinct("pedido_id").alias("pedidos_ultimos_90d"),
            F.sum("receita").alias("receita_ultimos_90d"),
        )
    )

    visitas = (
        spark.table("silver.visitas")
        .filter(F.col("data_visita") <= referencia)
        .groupBy("cliente_id")
        .agg(
            F.count(
                F.when(F.col("data_visita") > F.date_sub(referencia, JANELA_RECENTE_DIAS), 1)
            ).alias("visitas_ultimos_90d"),
            F.max("data_visita").alias("_ultima_visita"),
        )
    )

    oportunidades = (
        spark.table("silver.oportunidades")
        .filter(
            (F.col("data_abertura") <= referencia) & (~F.col("etapa").isin(ETAPAS_FECHADAS))
        )
        .groupBy("cliente_id")
        .agg(F.count(F.lit(1)).alias("oportunidades_abertas"))
    )

    # Atributos estáticos do cliente — seguros porque não mudam com o
    # futuro (diferente de total_pedidos/receita_acumulada de dim_cliente,
    # que agregam a base inteira e vazariam informação do pós-corte).
    clientes_estatico = spark.table("gold.dim_cliente").select(
        "cliente_id", "segmento", "data_cadastro"
    )

    df = (
        agregados.join(recente, "cliente_id", "left")
        .join(visitas, "cliente_id", "left")
        .join(oportunidades, "cliente_id", "left")
        .join(clientes_estatico, "cliente_id", "left")
    )

    df = df.withColumn(
        "recencia_dias", F.datediff(referencia, F.col("_ultimo_pedido"))
    ).withColumn(
        "intervalo_medio_dias",
        F.when(
            F.col("frequencia_pedidos") > 1,
            F.datediff(F.col("_ultimo_pedido"), F.col("_primeiro_pedido"))
            / (F.col("frequencia_pedidos") - 1),
        ),
    )

    # atraso_relativo é a feature-chave: recência frente ao ciclo de compra
    # do próprio cliente. NULL explícito para quem tem 1 pedido só (ou
    # ciclo zerado) — nunca um valor de "teto" por acidente de F.least().
    df = (
        df.withColumn(
            "atraso_relativo",
            F.when(
                (F.col("intervalo_medio_dias").isNotNull()) & (F.col("intervalo_medio_dias") > 0),
                F.col("recencia_dias") / F.col("intervalo_medio_dias"),
            ),
        )
        .withColumn("ticket_medio", F.col("valor_total") / F.col("frequencia_pedidos"))
        .withColumn(
            "dias_desde_primeiro_pedido", F.datediff(referencia, F.col("_primeiro_pedido"))
        )
        .withColumn("dias_desde_cadastro", F.datediff(referencia, F.col("data_cadastro")))
        .withColumn("pedidos_ultimos_90d", F.coalesce(F.col("pedidos_ultimos_90d"), F.lit(0)))
        .withColumn("receita_ultimos_90d", F.coalesce(F.col("receita_ultimos_90d"), F.lit(0.0)))
        .withColumn(
            "participacao_receita_90d_pct",
            F.when(
                F.col("valor_total") > 0,
                100 * F.col("receita_ultimos_90d") / F.col("valor_total"),
            ),
        )
        .withColumn(
            "taxa_devolucao_pct",
            100 * F.col("_itens_devolvidos") / F.col("_itens_totais"),
        )
        .withColumn("visitas_ultimos_90d", F.coalesce(F.col("visitas_ultimos_90d"), F.lit(0)))
        .withColumn("dias_desde_ultima_visita", F.datediff(referencia, F.col("_ultima_visita")))
        .withColumn(
            "oportunidades_abertas", F.coalesce(F.col("oportunidades_abertas"), F.lit(0))
        )
        .withColumn("multicanal", F.col("canais_distintos") > 1)
    )

    if com_alvo:
        janela_alvo = spark.table("gold.fato_vendas").filter(
            (F.col("data_pedido") >= referencia)
            & (F.col("data_pedido") < F.date_add(referencia, JANELA_ALVO_DIAS))
        )
        compradores = janela_alvo.select("cliente_id").distinct().withColumn(
            "comprou_em_7d", F.lit(1)
        )
        df = df.join(compradores, "cliente_id", "left").withColumn(
            "comprou_em_7d", F.coalesce(F.col("comprou_em_7d"), F.lit(0)).cast("int")
        )

    for coluna in COLUNAS_DOUBLE:
        df = df.withColumn(coluna, F.col(coluna).cast("double"))

    colunas_finais = [
        "cliente_id",
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
        "segmento",
        "multicanal",
    ]
    if com_alvo:
        colunas_finais.append("comprou_em_7d")

    return df.select(*colunas_finais).withColumn("_referencia", referencia)


# COMMAND ----------

COMENTARIOS_COLUNA = {
    "cliente_id": "Identificador do cliente — chave de grão da tabela.",
    "recencia_dias": "Dias entre a última compra (não cancelada) do cliente e a data de referência da tabela.",
    "frequencia_pedidos": "Número de pedidos distintos (não cancelados) do cliente até a data de referência.",
    "valor_total": "Receita líquida acumulada do cliente até a data de referência.",
    "ticket_medio": "valor_total dividido por frequencia_pedidos.",
    "intervalo_medio_dias": "Ciclo médio de compra do cliente (dias entre pedidos). NULL para cliente de um pedido só.",
    "atraso_relativo": "recencia_dias / intervalo_medio_dias — quão atrasado o cliente está frente ao próprio ritmo de compra. É a feature que ordena a fila de contato. NULL quando intervalo_medio_dias é NULL.",
    "dias_desde_primeiro_pedido": "Dias entre o primeiro pedido do cliente e a data de referência — tempo de casa como comprador.",
    "dias_desde_cadastro": "Dias entre o cadastro do cliente e a data de referência.",
    "pedidos_ultimos_90d": "Pedidos distintos do cliente nos 90 dias antes da data de referência (inclusive).",
    "receita_ultimos_90d": "Receita do cliente nos 90 dias antes da data de referência (inclusive).",
    "participacao_receita_90d_pct": "Percentual da receita histórica do cliente que veio dos últimos 90 dias antes da referência.",
    "categorias_distintas": "Número de categorias de produto distintas já compradas pelo cliente até a data de referência.",
    "marcas_distintas": "Número de marcas distintas já compradas pelo cliente até a data de referência.",
    "quantidade_itens_total": "Soma de unidades compradas pelo cliente até a data de referência, excluindo devoluções.",
    "taxa_devolucao_pct": "Percentual dos itens comprados pelo cliente que foram devolvidos.",
    "visitas_ultimos_90d": "Visitas comerciais recebidas pelo cliente nos 90 dias antes da data de referência.",
    "dias_desde_ultima_visita": "Dias desde a última visita comercial registrada até a data de referência. NULL se o cliente nunca recebeu visita.",
    "oportunidades_abertas": "Oportunidades comerciais do cliente ainda não fechadas (nem ganhas nem perdidas) até a data de referência.",
    "segmento": "Segmento comercial do cliente (de gold.dim_cliente — atributo estático, seguro para usar sem corte de data).",
    "multicanal": "True quando o cliente já comprou por mais de um canal de venda até a data de referência.",
    "comprou_em_7d": "1 se o cliente fez algum pedido não cancelado nos 7 dias a partir da data de referência (inclusive), 0 caso contrário. É o alvo do modelo — só existe em features_treino.",
    "_referencia": "Data de corte usada para calcular todas as colunas desta linha — nenhuma feature olha além dela.",
}


def gravar(df, tabela, descricao):
    df.write.mode("overwrite").option("overwriteSchema", "true").saveAsTable(f"gold.{tabela}")
    spark.sql(f"COMMENT ON TABLE gold.{tabela} IS '{descricao}'")
    for coluna, comentario in COMENTARIOS_COLUNA.items():
        if coluna in df.columns:
            spark.sql(
                f"COMMENT ON COLUMN gold.{tabela}.{coluna} IS '{comentario.replace(chr(39), chr(39)+chr(39))}'"
            )
    return spark.table(f"gold.{tabela}").count()


# COMMAND ----------

df_treino = montar_features("2026-08-01", com_alvo=True)
linhas_treino = gravar(
    df_treino,
    "features_treino",
    "Uma linha por cliente ativo até 2026-08-01, com o alvo comprou_em_7d — usada para treinar o modelo de propensão.",
)

df_cliente = montar_features("2026-08-31", com_alvo=False)
linhas_cliente = gravar(
    df_cliente,
    "features_cliente",
    "Uma linha por cliente ativo até 2026-08-31, sem alvo — usada para pontuar os 3.000 clientes com o modelo de propensão.",
)

# COMMAND ----------

taxa_base = df_treino.select(F.avg("comprou_em_7d")).first()[0]

print(f"features_treino:  {linhas_treino} clientes")
print(f"features_cliente: {linhas_cliente} clientes")
print(f"taxa base (comprou_em_7d): {taxa_base * 100:.2f}%")
