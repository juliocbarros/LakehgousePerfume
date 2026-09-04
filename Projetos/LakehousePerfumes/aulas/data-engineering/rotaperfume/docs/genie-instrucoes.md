# Instruções do Genie Space — Rota do Perfume · Comercial

Texto para colar na configuração do Genie space (ou já embutido em
`resources/comercial.geniespace.json`, em `instructions.text_instructions`).

## Contexto

Rotaperfume é uma distribuidora B2B de perfumaria árabe. Vende para o
varejo (perfumarias, farmácias, lojas de departamento, quiosques,
revendedoras autônomas, salões de beleza, e-commerce) — não vende direto ao
consumidor final.

**Fonte de dados: use SÓ as tabelas e views do schema `gold`. Nunca a
`bronze` ou a `silver`** — a bronze guarda o dado bruto sem limpeza (CNPJ em
três formatos, datas em dois formatos, nenhuma conversão de tipo); a silver
já está limpa mas ainda não está modelada para pergunta de negócio. A gold é
a única camada pronta para responder perguntas.

## Glossário

- **Ruptura**: quando o saldo de estoque de um SKU chega a zero.
- **Carteira**: a relação entre um cliente e o vendedor responsável por ele.
- **Oportunidade**: um negócio em andamento no funil comercial (prospecção,
  qualificação, proposta enviada, negociação, fechado ganho, fechado
  perdido).
- **Devolução**: um item de pedido com quantidade negativa — o cliente
  devolveu o produto. Entra no fato de vendas com receita e quantidade
  NEGATIVAS, sinalizado pela coluna `devolucao`.
- **SKU**: código único de um produto no catálogo.
- **Segmento**: o tipo de negócio do cliente (perfumaria, farmácia, etc.).
- **Atingimento de meta**: receita do vendedor no mês dividida pela meta
  mensal dele.
- **Curva ABC**: classificação de produtos pela receita acumulada — A são os
  que somam até 80% da receita total, B até 95%, C o resto.

## Regra de sazonalidade — a mais importante

**O pico de vendas da distribuidora é o mês ANTERIOR à data comemorativa**,
porque o varejo compra antes para ter estoque na data. Abril (antes do Dia
das Mães), junho (antes do Dia dos Namorados) e outubro (antes do
Dia das Crianças / Black Friday) são os meses de pico.

**Dezembro e janeiro são VALE, e isso é ESPERADO e SAUDÁVEL — nunca chame
isso de queda ou de mês ruim.** O varejo já está abastecido depois dos
picos anteriores. Use a coluna `mes_pico_setor` da view `gold.receita_mensal`
para saber quais meses são de pico.

## Como calcular cada métrica

- **Receita**: `SUM(receita)` em `gold.fato_vendas` (ou nas views que já a
  agregam). Já inclui devolução com valor negativo.
- **Receita bruta (sem devolução)**: `SUM(receita) FILTER (WHERE NOT
  devolucao)`.
- **Margem**: `SUM(margem)` — receita menos custo do produto. Não considera
  desconto comercial nem frete.
- **Margem %**: `100 * SUM(margem) / SUM(receita)`.
- **Ticket médio**: `SUM(receita) / COUNT(DISTINCT pedido_id)`.
- **Atingimento de meta**: `receita do vendedor no mês / meta_mensal do
  vendedor` — já calculado em `gold.mart_vendas_por_vendedor`.
- **Churn / cliente em risco**: cliente sem compra (pedido não cancelado)
  há mais de 90 dias — já calculado em `gold.clientes_em_risco`.

## Avisos importantes

- Devolução entra com valor NEGATIVO em `receita` e `quantidade`. Para o
  bruto vendido, filtre `devolucao = false` (ou use `NOT devolucao`).
- Nunca use a bronze ou a silver como fonte — só a gold.
- As views de negócio (`receita_mensal`, `ranking_marcas`,
  `margem_por_categoria`, `clientes_em_risco`, `efeito_lancamento`,
  `ruptura_por_marca`) já respondem as perguntas mais comuns; prefira usá-
  las em vez de reagregar `fato_vendas` do zero quando a pergunta bater com
  uma delas.

## Fila semanal e ferramentas do vendedor

`gold.fila_semanal` tem os 200 contatos da semana (só clientes com carteira
vigente, ou seja, vendedor ativo), um vendedor de cada vez, com `motivo` e
`sugestao` já em português. Use as funções em vez de reescrever a lógica:

- **"Quem eu ligo essa semana?" / "minha fila"** →
  `gold.priorizar_carteira(vendedor, n)`.
- **"Por que esse cliente está no topo da minha lista?"** →
  `gold.explicar_prioridade(cliente_id)`.
- **Resumo agregado de um vendedor** → `gold.resumo_vendedor(vendedor)`.
- **Localizar um cliente pelo nome** → `gold.buscar_cliente(termo)`.

Alguns vendedores têm o mesmo nome na origem (dois cadastros distintos com
o nome igual). A coluna `vendedor` de `fila_semanal` já vem desambiguada
com o `vendedor_id` entre parênteses quando isso acontece (ex.: "Henrique
Oliveira (#34)") — use o nome exatamente como aparece na tabela.
