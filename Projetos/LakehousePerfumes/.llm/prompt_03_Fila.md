# Prompt 3 · A fila e o agente

**Slides 38 a 45 · ~18 minutos · 3º deploy da noite**

> Todas as queries deste passo, prontas para colar: [`QUERIES.md`](QUERIES.md)

## O que este prompt faz

Pega os 200 maiores scores da base inteira, cruza com a carteira de cada
vendedor e escreve a lista da semana **em português**: quem ligar, por quê e o
que oferecer. Cria as quatro funções que o agente consulta, **e a aba do
dashboard onde o vendedor vê a lista**.

No fim existe `gold.fila_semanal` — e ela é a resposta literal ao que o diretor
perguntou no slide 2.

---

## 1 · Antes de colar (3 min)

**SQL Editor.** Mostre o score cru, como ele sai do modelo:

```sql
SELECT cliente_id, ROUND(score, 4) AS score, faixa
FROM lakehouse_rotaperfume.gold.score_propensao
ORDER BY score DESC LIMIT 5;
```

> *"Está certíssimo e é inútil. Entregue isso para o vendedor e ele volta a
> ligar pela intuição na segunda-feira."*

**Depois faça a pergunta que decide o desenho da tabela:**

> *"São 200 ligações e 42 vendedores. Dou 5 para cada um, ou dou os 200
> melhores da base inteira?"*

A sala responde "5 para cada, é mais justo". E aí: *"justo com quem? Se a
carteira do João está quente e a do Pedro está fria, a cota igual obriga o
João a deixar cliente quente na mesa."*

---

## 2 · Colar o prompt

Bloco **## O prompt** de
[`../prd/prompt-03-fila-e-agente.md`](../prd/prompt-03-fila-e-agente.md).

---

## 3 · Enquanto ele trabalha

Slides **39 a 42**:

- **39** — batch ou tempo real *(pule se estiver atrasado)*
- **40** — o último metro, onde os projetos de ML morrem
- **41** — as quatro ferramentas: ele não inventa, ele consulta
- **42** — a resposta para o diretor

---

## 4 · Rode só a tarefa (35s, não 3m30)

```bash
cd aulas/aula-02-engenharia-de-dados/rotaperfume
bash scripts/rodar-tarefa.sh <perfil> ml_fila
```

O job completo fica para o fim da noite, quando você vai mostrar o DAG inteiro.

---

## 5 · Quando terminar: onde clicar

- [ ] **Catalog** → `gold` → `fila_semanal` → **Sample data**
- [ ] Ainda em `gold`, role até **Functions**: as quatro estão lá,
      cada uma com o COMMENT que o agente lê
- [ ] **Jobs & Pipelines** → o DAG fechou com `ml_fila`. **15 tarefas.**
      Abra a tela inteira e deixe a sala olhar por três segundos
- [ ] **Genie** (menu da esquerda) → o espaço comercial → confirme que
      `fila_semanal` está entre as tabelas

---

## 6 · A query que prova

```sql
-- 1. A LISTA. É o slide 42 saindo do banco.
SELECT vendedor, ordem, razao_social, ROUND(score, 2) AS score, motivo
FROM lakehouse_rotaperfume.gold.fila_semanal
WHERE vendedor = (SELECT vendedor FROM lakehouse_rotaperfume.gold.fila_semanal
                  GROUP BY vendedor ORDER BY COUNT(*) DESC LIMIT 1)
ORDER BY ordem;

-- 2. A conta fecha, e a distribuição conta uma história
SELECT COUNT(DISTINCT vendedor) AS vendedores, COUNT(*) AS ligacoes
FROM lakehouse_rotaperfume.gold.fila_semanal;
-- 200 ligações em ~36 vendedores. São 36 e não 42 porque seis estão
-- desligados com carteira vinculada: a sujeira nº 9 cobrando o preço.

-- 3. A ferramenta, chamada como o agente chamaria
SELECT * FROM lakehouse_rotaperfume.gold.priorizar_carteira('Débora Souza', 5);
```

**Leia a primeira linha da lista em voz alta e pare.** É o fim do argumento.

---

## 7 · ONDE O VENDEDOR VÊ OS 200

Três portas para o mesmo dado. Mostre nesta ordem:

### a) O dashboard — a tela dele

**Dashboards** (menu da esquerda) → *Rota do Perfume · Comercial* → aba
**Fila da semana**. Escolha um vendedor no filtro: aparecem os contatos dele,
em ordem, com motivo e sugestão.

> É a resposta literal ao que o diretor pediu no slide 2. **Abra em tela cheia
> e deixe a sala ler uma linha.**

### b) A query — o plano B, e o que está por trás

**Se o dashboard não abrir, não carregar ou o filtro travar**, cole isto no
**SQL Editor**. É exatamente o que o dashboard faz:

```sql
-- A FILA DE UM VENDEDOR. Troque o nome e pronto.
SELECT ordem                     AS `#`,
       razao_social              AS cliente,
       cidade,
       ROUND(score, 2)           AS nota,
       faixa,
       motivo                    AS por_que_ligar,
       sugestao                  AS o_que_oferecer
FROM   lakehouse_rotaperfume.gold.fila_semanal
WHERE  vendedor = 'Débora Souza'       -- ← troque aqui
ORDER  BY ordem;
```

E, se não souber o nome de nenhum vendedor, comece por esta — ela mostra quem
tem mais contatos na semana:

```sql
-- QUEM RECEBEU QUANTOS CONTATOS
SELECT vendedor,
       COUNT(*)               AS contatos,
       ROUND(AVG(score), 2)   AS nota_media
FROM   lakehouse_rotaperfume.gold.fila_semanal
GROUP  BY vendedor
ORDER  BY contatos DESC;
```

```sql
-- A FILA INTEIRA, do maior score para o menor — os 200, de uma vez
SELECT vendedor, ordem, razao_social, ROUND(score,2) AS nota, motivo
FROM   lakehouse_rotaperfume.gold.fila_semanal
ORDER  BY score DESC;
```

> **Deixe estas três queries abertas numa aba do SQL Editor antes de começar a
> noite.** Se o dashboard falhar ao vivo, você troca de aba e continua sem
> perder o fio.

### c) O Genie — a pergunta em português

#### E aí sim, o agente (5 min)

Abra o Genie e pergunte **com as palavras do vendedor**:

- [ ] *"Quem eu ligo essa semana?"*
- [ ] *"Por que esse cliente está no topo da minha lista?"*

**Mostre o SQL que o Genie gerou.** É a diferença entre agente e chute: a
resposta tem query embaixo.

---

## 8 · O fechamento

Slides **43 a 45**: o antes e o depois, o arco das três noites, a frase.

> *"Dashboard descreve o passado. Modelo prevê o futuro. Agente diz o que fazer
> na segunda de manhã. E vocês construíram junto — não assistiram."*

**Só então abra o carrinho.** A prova é o argumento de venda.

---

## Se der errado

| O que aparece | O que fazer |
|---|---|
| `CREATE FUNCTION` falha com coluna ambígua | parâmetro com nome igual ao de uma coluna — peça o prefixo `p_` |
| `RETURNS TABLE` recusado no workspace | plano B: as quatro viram **views** `gold.ferramenta_*`. O argumento é o mesmo |
| A fila veio com ~172 linhas | o descarte de vendedor desligado rodou depois do `LIMIT 200`. Peça para filtrar antes de limitar |
| `motivo` com `NULL` no meio | faltou o `ELSE` no `CASE WHEN`. O teste 2 pegou: é o teste funcionando |
| O Genie inventou um número | a instrução não entrou no espaço. Mostre o antes e o depois — vale mais que dez slides sobre alucinação |
| O deploy do Genie reclama de ordenação | tabelas e colunas do `geniespace.json` têm que estar em ordem alfabética, e só pode haver **uma** instrução de texto |
| `PERMISSION_DENIED ... Table 'fila_semanal' does not exist` | o Genie não aceita tabela que ainda não existe. **Crie a tabela primeiro, deploye depois** |