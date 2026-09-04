# Rota do Perfume — Lakehouse Analytics Platform

A production-style **Databricks Lakehouse** built end-to-end for *Rotaperfume*, a fictional B2B distributor of Arabian perfumery selling into retail (perfumeries, pharmacies, department stores, kiosks, independent resellers, beauty salons, e-commerce).

The project takes ~313K rows of raw ERP/CRM data and turns them into a governed, tested, documented analytics platform — with an AI/BI dashboard, a purchase-propensity ML model, and a natural-language (Genie) assistant sitting on top — using **Databricks Asset Bundles** so the entire catalog, pipeline, dashboard, model, and AI agent are defined as code and deployed with a single command.

> This repository's active project lives in [`Projetos/LakehousePerfumes`](Projetos/LakehousePerfumes).

---

## What this project demonstrates

- **Infrastructure as code**: the whole Unity Catalog object graph (catalog, schemas, volumes, tables, views), the orchestration job, the BI dashboard, and the Genie AI agent are all version-controlled JSON/YAML/SQL, deployed via `databricks bundle deploy`.
- **The medallion architecture, done properly**: raw files are never touched; bronze preserves source data byte-for-byte as strings; silver is where cleaning, typing, and deduplication happen — with the business rules enforced as **Delta CHECK constraints**, not just code comments; gold is modeled for consumption (star schema + purpose-built business views), never raw.
- **Data quality as a first-class citizen**: 9 automated data tests and a metadata-completeness audit run as part of every pipeline execution and **fail the job** if a number stops reconciling or a column loses its documentation — not a report nobody reads.
- **AI-ready data**: the reason a natural-language agent (Genie) can answer real business questions accurately is that the data underneath it is clean, typed, documented, and modeled — not because the model got smarter.
- **MLOps, not a notebook that only runs once**: a purchase-propensity model is trained with point-in-time-correct features (no leakage), registered to **Unity Catalog** right alongside the tables it was trained on, gated by three `assert`s that fail the job if the model doesn't beat chance or looks suspiciously perfect, and consumed by both a dashboard page and four Genie-callable SQL functions — so the model's answer is auditable, not a black box.

## Architecture

```mermaid
flowchart LR
    subgraph Source["Source Systems"]
        ERP[ERP CSVs<br/>produtos · pedidos · itens_pedido<br/>pagamentos · estoque]
        CRM[CRM CSVs<br/>clientes · vendedores · carteira<br/>oportunidades · visitas]
    end

    subgraph UC["Unity Catalog: lakehouse_rotaperfume"]
        direction TB
        RAW["<b>bronze.raw</b> (Volume)<br/>10 CSVs, byte-for-byte"]
        BRONZE["<b>bronze</b> (10 Delta tables)<br/>all STRING, zero cleanup<br/>+ arrival-check control table"]
        SILVER["<b>silver</b> (10 Delta tables)<br/>typed, cleaned, deduplicated<br/>5 CHECK constraints"]
        GOLD["<b>gold</b><br/>4 dimensions · fato_vendas (191K rows)<br/>3 data marts · 6 business views"]
        ML["<b>gold (ML)</b><br/>features_treino/cliente · score_propensao<br/>fila_semanal · propensao_compra model"]
        RAW --> BRONZE --> SILVER --> GOLD --> ML
    end

    ERP --> RAW
    CRM --> RAW

    GOLD --> DASH[AI/BI Dashboard]
    ML --> DASH
    GOLD --> GENIE[Genie Space<br/>Natural-language Q&A]
    ML --> GENIE
```

### Pipeline orchestration

A single Lakeflow Job (`rotaperfume_pipeline`) runs all 15 tasks end-to-end, serverless, on a daily schedule:

```mermaid
flowchart TD
    A[raw_conferencia<br/>verifies all 10 files arrived] --> B[bronze_ingestao<br/>one ingestion function, 10 tables]
    B --> C1[silver_clientes]
    B --> C2[silver_pedidos]
    B --> C3[silver_itens_produtos]
    B --> C4[silver_crm_financeiro]
    C1 & C2 & C3 & C4 --> D[gold_dimensoes]
    D --> E[gold_fato_vendas]
    E --> F[gold_marts]
    F --> G[testes<br/>9 data-quality checks]
    F --> H[metricas_de_negocio<br/>6 business views]
    H --> I[auditoria_de_metadado<br/>fails the job on undocumented columns]
    I --> J[ml_features<br/>point-in-time features, two cutoffs]
    J --> K[ml_modelo<br/>train + register + score, 3 asserts]
    K --> L[ml_fila<br/>top-200 weekly call queue]
```

Silver tables run in parallel (independent transformations); gold builds sequentially since each layer depends on the previous one; two branches — data-quality tests and the metadata audit — are gold's last line of defense and **halt the job** on failure rather than let bad data reach the dashboard or the AI agent. The ML stage only starts once both of those pass, so the model never trains on unvalidated data.

## Tech stack

| Layer | Technology |
|---|---|
| Compute & storage | Databricks (fully serverless), Delta Lake |
| Governance | Unity Catalog (catalogs, schemas, managed volumes, managed tables, CHECK constraints) |
| Orchestration | Lakeflow Jobs (formerly Databricks Workflows) |
| Transformations | PySpark notebooks (raw/bronze/ML) + Spark SQL (silver/gold) |
| Machine learning | scikit-learn (`HistGradientBoostingClassifier`), tracked and registered with **MLflow** on Unity Catalog |
| Infrastructure as code | Databricks Asset Bundles (DABs) — `databricks.yml` + `resources/*.yml` |
| BI | Databricks AI/BI Dashboards (Lakeview), defined as versioned JSON |
| AI / natural language | Databricks Genie Space, defined as versioned JSON with deterministic example-query IDs, backed by 4 Unity Catalog SQL functions |
| CLI / tooling | Databricks CLI, driven by Claude Code with the Databricks AI Tools skill set |

## Repository structure

```
Projetos/LakehousePerfumes/
├── dados/                          # Source CSVs (ERP + CRM), ~313K rows total
│   ├── erp/                        # produtos, pedidos, itens_pedido, pagamentos, estoque
│   └── crm/                        # clientes, vendedores, carteira, oportunidades, visitas
├── .llm/                           # The design prompts this project was built from
└── aulas/engenharia-de-dados/rotaperfume/   # The Databricks Asset Bundle
    ├── databricks.yml              # Bundle definition, targets (dev/prod), variables
    ├── scripts/                    # Catalog bootstrap, raw file upload, single-task runner
    ├── resources/                  # Bundle resources: job, dashboard, Genie space
    │   ├── catalogo.yml            #   Unity Catalog schemas + volume
    │   ├── pipeline.job.yml        #   The 15-task orchestration job
    │   ├── dashboard.dashboard.yml #   AI/BI dashboard resource
    │   ├── genie.genie_space.yml   #   Genie space resource
    │   └── comercial.geniespace.json #  Genie space definition
    ├── src/
    │   ├── raw/                    # Arrival-check notebook
    │   ├── bronze/                 # Single-function ingestion notebook (10 tables)
    │   ├── silver/                 # Cleaning + typing + constraints (4 SQL scripts)
    │   ├── gold/                   # Dimensions, fact table, marts, business views, tests,
    │   │                           # weekly call queue + Genie-callable SQL functions
    │   ├── ml/                     # Point-in-time features, model training + registration
    │   └── dashboards/             # Dashboard JSON source (Comercial + Fila da semana pages)
    └── docs/                       # Genie instructions (business glossary, seasonality rules)
```

## Data quality & governance

- **Silver-layer contracts**: CNPJ normalized to 14 digits (never cast to a number), dates parsed defensively (`try_to_date`, never `to_date`, because ANSI mode aborts on malformed input instead of returning `NULL`), duplicate customer records merged with full audit trail, returns and cancellations *flagged, never dropped*.
- **5 Delta CHECK constraints** enforced at the table level (e.g. `pedido_cancelado_zerado: NOT cancelado OR valor_liquido = 0`) — a constraint that rejects a bad write is a rule the *table* enforces, independent of whatever script runs against it.
- **9 automated tests** on every pipeline run, including the one that matters most: gold revenue must equal silver revenue to the cent (**R$ 102,303,828.05**) — a cleanup pass is only correct if it doesn't change the top-line number.
- **100% metadata coverage** on the gold layer, audited on every run: every table, view, and business-critical column must carry a `COMMENT` describing its business meaning — because that's exactly what the Genie agent reads to decide which column to use.

## Business layer

Six views, named the way a business stakeholder would ask for them (not `mart_produto_performance` — `ranking_marcas`, `clientes_em_risco`, `margem_por_categoria`...), each documented with the *question* it answers rather than its technical shape:

| View | Answers |
|---|---|
| `receita_mensal` | How did revenue and margin trend month over month, and which months are seasonal peaks? |
| `ranking_marcas` | Which brands sell the most, at what margin, and what share of revenue? |
| `margem_por_categoria` | Which category actually makes money — the highest-revenue one isn't always the most profitable |
| `clientes_em_risco` | Which customers have gone quiet (90+ days), and how much monthly revenue is at stake? |
| `efeito_lancamento` | Do new product launches really outsell their post-launch baseline? |
| `ruptura_por_marca` | Which brands run out of stock most often? |

## Machine learning: who to call this week

On top of the gold layer, a purchase-propensity pipeline turns "3,000 customers" into "these 200, in this order, and here's why":

- **Point-in-time features** (`gold.features_treino` / `gold.features_cliente`): ~20 behavioral columns (recency, order cadence, 90-day momentum, return rate, CRM engagement) recomputed from `fato_vendas` for two cutoff dates — never from a whole-history table like `dim_cliente`, which would leak the future into the training label.
- **Model**: a `HistGradientBoostingClassifier` trained to predict `comprou_em_7d` (bought within 7 days of the cutoff), evaluated against three hand-computed baselines (last-purchase recency, lifetime value, and the engineered "overdue ratio" feature — which alone gets closer to the model's AUC than the other two combined). Three `assert`s gate promotion: the model must beat a coin flip, it must beat random selection on lift, and — the one that catches leakage — it must **not** be suspiciously close to perfect.
- **Registered to Unity Catalog** (`gold.propensao_compra`, alias `@prod`) right next to the tables it reads, versioned and tracked in MLflow like any other governed asset.
- **`gold.fila_semanal`**: the model's scores joined against each rep's *active* customer portfolio (excluding terminated reps' orphaned assignments — a real data-quality edge case this join has to handle), ranked and capped at 200 contacts total, each with a plain-language reason (`motivo`) and talking point (`sugestao`).
- **Four Genie-callable SQL functions** (`priorizar_carteira`, `explicar_prioridade`, `resumo_vendedor`, `buscar_cliente`) so the agent answers "who do I call this week?" by calling a function and reading the result — never by inventing a number.

## Getting started

```bash
cd Projetos/LakehousePerfumes/aulas/engenharia-de-dados/rotaperfume

databricks bundle validate --target dev --profile <your-profile>
databricks bundle deploy   --target dev --profile <your-profile>
databricks bundle run rotaperfume_pipeline --target dev --profile <your-profile>

# Or run a single task without waiting for the full pipeline:
bash scripts/rodar-tarefa.sh <your-profile> ml_fila
```

Requires the [Databricks CLI](https://docs.databricks.com/dev-tools/cli/install.html) and a workspace with Unity Catalog and a SQL warehouse.

## Project origin

This platform was built iteratively across a sequence of self-contained design prompts (preserved in [`.llm/`](Projetos/LakehousePerfumes/.llm)), each one a complete deployable increment: raw ingestion → bronze → silver with data contracts → gold modeling and testing → BI dashboard → natural-language AI layer → point-in-time ML features → model training and registration → weekly call queue and agent tooling. Every increment was deployed and numerically verified against the source data before moving to the next.
