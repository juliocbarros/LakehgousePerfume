# Brief: recriar o Lakehouse Olist no Microsoft Fabric

Este documento é o ponto de partida para o Claude Code (VS Code) recriar,
dentro do Microsoft Fabric, o mesmo pipeline medalhão que já existe no
Databricks em `C:\Users\julio\OneDrive\Documentos\Projetos\Olist\Olist_DataEnginier`.
Não é um port automático — a arquitetura do Fabric é diferente o
suficiente em alguns pontos que vale reconstruir, não copiar e colar.

## Objetivo

Mesmo resultado final (raw → bronze → silver → gold → relatório), mesma
fonte de dados (os 9 CSVs da Olist), mesmas regras de negócio e as mesmas
pegadinhas já mapeadas — só que rodando 100% dentro de um workspace do
Fabric, com Lakehouse nativo, notebooks Fabric, Data Pipeline para
orquestração, e um modelo semântico em **Direct Lake** (não Import, não
DirectQuery) alimentando o relatório Power BI direto no mesmo workspace.

## Pré-requisito que precisa ser confirmado ANTES de começar

O Fabric exige uma **capacidade** atribuída ao workspace (trial de 60 dias,
ou uma capacidade F SKU paga, ou Power BI Premium). Sem isso, não dá pra
criar Lakehouse nem rodar notebook. Primeira coisa a checar/criar:
`app.fabric.microsoft.com` → Configurações da conta → "Iniciar teste
gratuito do Fabric" (se ainda não tiver uma capacidade ativa).

## De onde vêm os dados

Mesmos 9 CSVs, mesmo lugar, sem mudança:
```
C:\Users\julio\OneDrive\Documentos\Dados & Analytics\Base de teste\Base_Olist\Olist_new
```
customers, geolocation, orders, order_items, order_payments, order_reviews,
products, sellers, product_category_name_translation.

## Mapeamento de conceitos: Databricks → Fabric

| Databricks (o que já existe) | Fabric (o que construir) |
|---|---|
| Catálogo `lakehouse_olist` + schemas bronze/silver/gold (Unity Catalog) | Um **Lakehouse** por camada (`lh_bronze`, `lh_silver`, `lh_gold`) OU um único Lakehouse com *schemas* habilitados (Fabric lakehouse com schema support) — decidir com base no que o workspace do usuário suporta; documentar a escolha |
| Volume `bronze.raw` (landing zone) | Seção **Files** do Lakehouse bronze (`Files/raw/`) — upload manual ou via notebook |
| `src/raw/conferencia.py`, `src/bronze/ingestao.py` (notebooks Databricks) | **Notebooks Fabric** (PySpark), mesma lógica, trocando `dbutils`/paths de Volume por `notebookutils` e caminhos `Files/` do Lakehouse |
| `src/silver/*.sql`, `src/gold/*.sql` (SQL Warehouse) | Células `%%sql` dentro de notebooks Fabric, ou o **Lakehouse SQL analytics endpoint** (gerado automaticamente por cada Lakehouse, somente leitura) para consultas; escrita continua via notebook/Spark |
| `resources/pipeline.job.yml` (Databricks Job, 11 tasks) | **Data Pipeline** do Fabric, com atividades "Notebook" encadeadas pelas mesmas dependências (raw → bronze → 5 silver em paralelo → gold_dimensoes → fato_vendas → marts → testes/métricas) |
| `databricks.yml` (Asset Bundle, CLI deploy) | **Fabric Git integration**: conectar o workspace do Fabric ao mesmo repo `juliocbarros/olist-lakehouse` (ou um novo), branch dedicada; o Fabric sincroniza os itens do workspace (notebooks, pipeline, lakehouse) como arquivos no repo. Alternativa mais "código" pro Claude Code: `fab` CLI (Fabric command-line, `pip install ms-fabric-cli`) para criar itens via terminal, similar ao `databricks bundle` |
| GitHub Actions + OIDC (Service Principal Databricks) | Mesma ideia, mas autenticando com **Service Principal do Entra ID** (Azure AD) + Fabric REST API; ou, mais simples pra começar, usar só a Git integration nativa do Fabric (sync manual/automático pela UI, sem OIDC) |
| SQL Warehouse (`7c3ea71f9ae30d85`) + Power BI conectado via Databricks.Catalogs (Import) | **Nenhuma conexão externa** — o modelo semântico do Fabric lê os Delta tables do Lakehouse gold direto em **Direct Lake mode**: sem import, sem refresh manual, sem driver ODBC, sem popup de autenticação. Criar via "New semantic model" apontando pro Lakehouse gold |
| `Project_Olist.pbix` (Power BI Desktop local) | Relatório Power BI **nativo do workspace Fabric**, conectado ao modelo Direct Lake acima. Pode reaproveitar o layout de páginas já validado (Visão Geral, Categoria, Entrega, Geografia, Clientes) |

## O que NÃO muda — reaproveitar 1:1

- **Schema das 9 tabelas bronze** — mesmos nomes de arquivo, mesmas colunas
- **Toda a lógica de silver**: normalização de CEP (`lpad` a 5 dígitos),
  `try_to_timestamp` em vez de `to_date` direto, dedup de avaliações por
  `review_id`, agregação de geolocalização por `cep_prefixo`
- **A pegadinha central**: `customer_id` é por pedido, `customer_unique_id`
  é a pessoa — `dim_cliente` tem que agregar por `customer_unique_id`,
  exatamente como no Databricks
- **O grão de `fato_vendas`**: item de pedido, com pagamento/avaliação do
  pedido inteiro repetido por item (documentar de novo pra não reintroduzir
  o bug de dupla contagem)
- **Os 9 testes de qualidade** — reescrever como células de notebook que
  fazem `assert` (ou `raise Exception`) em vez do `raise_error` do
  Databricks SQL; mesma lista de checagens (receita batendo entre camadas,
  órfãos, nota entre 1 e 5, volume esperado, soma dos marts = fato)
- **Os meses de pico do varejo brasileiro** (maio, agosto, novembro,
  dezembro) na `dim_calendario`

## O que muda de verdade (avisar o usuário quando encontrar)

- Sintaxe Spark é quase idêntica, mas `dbutils.fs`/`dbutils.widgets` viram
  `notebookutils.fs`/`notebookutils` no Fabric — não é drop-in
  automático, precisa trocar linha por linha
- Não existe Unity Catalog `GRANT` no Fabric — permissão é por item do
  workspace (papéis Admin/Member/Contributor/Viewer) ou, pra dado mais
  granular, OneLake data access roles — modelo de segurança diferente,
  vale uma seção própria depois que o pipeline básico estiver de pé
- Direct Lake tem uma pegadinha própria: se a tabela Delta tiver muitos
  arquivos pequenos (VOrder desabilitado, muitos merges), o Fabric pode
  cair de Direct Lake para DirectQuery silenciosamente — rodar
  `OPTIMIZE`/`VACUUM` nas tabelas gold ajuda a manter o modo rápido

## Passo a passo sugerido pro Claude Code

1. Confirmar capacidade Fabric ativa (pré-requisito acima)
2. Criar o workspace (ou usar um existente) e os Lakehouses bronze/silver/gold
3. Subir os 9 CSVs pra `Files/raw/` do Lakehouse bronze
4. Portar `src/raw/conferencia.py` e `src/bronze/ingestao.py` para notebooks
   Fabric, trocando `dbutils` → `notebookutils` e caminhos de Volume →
   caminhos de Files
5. Portar os 5 SQL de silver e os 5 de gold para células `%%sql` de
   notebooks, apontando pros Lakehouses corretos (`lakehouse_silver.tabela`
   em vez de `lakehouse_olist.silver.tabela`)
6. Criar o Data Pipeline replicando as 11 dependências do
   `resources/pipeline.job.yml`
7. Criar o modelo semântico em Direct Lake sobre o Lakehouse gold, com as
   mesmas 5 dimensões + fato_vendas, os mesmos relacionamentos e as mesmas
   9 medidas DAX (a tabela `Medidas` também)
8. Recriar o relatório com as 5 páginas já desenhadas
9. Conectar o workspace ao Git (mesmo repo ou um novo) pra ter histórico

## Referência: onde ver o projeto Databricks original

`C:\Users\julio\OneDrive\Documentos\Projetos\Olist\Olist_DataEnginier\` —
em especial `README.md`, `.llm\prompt_01.md` (pipeline completo) e
`.llm\prompt_02.md` (CI/CD) para o histórico de decisões já tomadas.
