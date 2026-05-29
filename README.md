# DB-Cluster-PostgreSQL-and-NodeJS-App

Container project for monitoring on Datadog. Laboratório que reproduz o cenário **Movida**: aplicações **Node.js** conectando a um **cluster PostgreSQL** através de camada de **load balancing** (simulando **ALB/NLB** na AWS), com observabilidade completa no **Datadog** via **Datadog Agent**.

Repositório: [github.com/battlehopper/DB-Cluster-PostgreSQL-and-NodeJS-App](https://github.com/battlehopper/DB-Cluster-PostgreSQL-and-NodeJS-App)

---

## Arquitetura

```text
                         ┌─────────────────────┐
                         │   Datadog Agent     │
                         └──────────┬──────────┘
                                    │
┌──────────────┐    HTTP :8080      │      ┌─────────────┐
│   Cliente    │ ───────────────►   │      │  api-1/2    │
└──────────────┘      alb-app      │      └──────┬──────┘
                                    │             │ PG :5432
                                    │      ┌──────▼──────┐
                                    │      │ haproxy-db  │  LB externo (NLB)
                                    │      └──────┬──────┘
                                    │      ┌──────▼──────┐
                                    │      │  pg-router  │  Router PG
                                    │      │ 6446 write  │  (conceito SPQR /
                                    │      │ 6447 read   │   MySQL Router)
                                    │      └──────┬──────┘
                                    │    ┌────────┴────────┐
                                    │    │                 │
                                    │ pg-primary      pg-replica
                                    │  (PRIMARY)       (SECONDARY)
```

| Componente | Papel no lab | Equivalente Movida |
|------------|--------------|-------------------|
| `alb-app` | ALB HTTP das APIs | Application Load Balancer |
| `haproxy-db` | LB TCP externo | NLB (`10.220.10.10`) |
| `pg-router` | Router escrita/leitura | MySQL Router / [SPQR](https://www.postgresql.org/about/news/stateless-postgres-query-router-100-released-2759/) |
| `pg-primary` / `pg-replica` | Cluster PostgreSQL | DB-02 PRIMARY / DB-01,03 SECONDARY |

---

## Stack de containers

| Container | Imagem | Porta (host) |
|-----------|--------|--------------|
| `haproxy-db` | haproxy:2.9 | 5432 (LB), 5433 (LB read) |
| `pg-router` | haproxy:2.9 | **6446** (write), **6447** (read) |
| `pg-primary` | postgres:16-alpine | interna |
| `pg-replica` | build local | interna |
| `api-1`, `api-2` | build local (Node 20) | interna |
| `alb-app` | nginx:1.27 | **8080** |
| `datadog-agent` | agent:7 | 8126 (APM), 8125 (DogStatsD) |
| `loadgen` (opcional) | curl | profile `loadgen` |

---

## Pré-requisitos

- EC2 com **4 GB RAM** recomendado (mínimo 2 GB)
- Docker + Docker Compose v2
- **API Key** Datadog com permissões de métricas, logs e APM
- Security Group liberando **8080** (demo) e restringindo **5432/5433** à VPC

---

## Receita rápida — EC2 (Amazon Linux / Ubuntu)

### 1. Provisionar EC2

- AMI: Amazon Linux 2023 ou Ubuntu 22.04+
- Tipo: `t3.medium` ou superior
- Disco: 30 GB+
- IAM: opcional (não obrigatório para este lab; API key vai no `.env`)

### 2. Bootstrap automático

```bash
curl -fsSL https://raw.githubusercontent.com/battlehopper/DB-Cluster-PostgreSQL-and-NodeJS-App/main/scripts/ec2-bootstrap.sh -o ec2-bootstrap.sh
chmod +x ec2-bootstrap.sh
./ec2-bootstrap.sh
newgrp docker
```

### 3. Configurar Datadog

```bash
cd /opt/movida-datadog-lab
cp .env.example .env
nano .env   # defina DD_API_KEY e senhas
```

### 4. Subir o ecossistema

```bash
chmod +x scripts/compose.sh
./scripts/compose.sh up -d --build
./scripts/compose.sh ps
./scripts/compose.sh logs -f --tail=50
```

> Se `docker compose` não existir na EC2, **`./scripts/compose.sh` instala automaticamente** o binário em `bin/docker-compose` (sem precisar de plugin). Alternativa: `./scripts/install-docker-compose.sh`

A replica pode levar **1–2 minutos** no primeiro `pg_basebackup`.

### 5. Validar

```bash
./scripts/smoke-test.sh
# ou manualmente:
curl http://$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4):8080/health
```

### 6. (Opcional) Tráfego contínuo para DBM/APM (a cada 1 min)

**Na EC2 (host):**
```bash
chmod +x scripts/continuous-traffic.sh
./scripts/continuous-traffic.sh
# ou em background:
nohup ./scripts/continuous-traffic.sh >> /var/log/movida-traffic.log 2>&1 &
```

**Via Docker (recomendado):**
```bash
./scripts/compose.sh --profile traffic up -d traffic-loop
./scripts/compose.sh logs -f traffic-loop
```

Variáveis opcionais: `INTERVAL_SECONDS=60`, `BASE_URL=http://localhost:8080`, `TRAFFIC_INTERVAL_SECONDS=60`.

### 7. (Opcional) Gerar tráfego sintético intenso

```bash
docker compose --profile loadgen up -d loadgen
```

---

## Endpoints da API (via ALB simulado — porta 8080)

| Método | Rota | Descrição |
|--------|------|-----------|
| GET | `/health` | Health check (usado pelo ALB) |
| GET | `/ready` | Readiness |
| GET | `/api/status` | Mostra nó PostgreSQL atendendo a query |
| GET | `/api/reservas` | Lista reservas |
| POST | `/api/reservas` | Cria reserva `{"cliente","veiculo","dias"}` |
| GET | `/api/metrics/load` | Gera carga sintética no banco |

---

## Unified Service Tagging (UST) + DBM

Seguimos a [documentação oficial de UST](https://docs.datadoghq.com/getting_started/tagging/unified_service_tagging/?tab=docker): tags reservadas **`env`**, **`service`** e **`version`** em todos os containers.

| Componente | `service` (UST) | Papel no DBM |
|------------|-----------------|--------------|
| `movida-reservas-api` | API Node (APM) | Origem das queries; `DD_DBM_PROPAGATION_MODE=full` |
| `movida-pg-haproxy` | LB externo (NLB) | Entrada da app (`PGHOST=haproxy-db`) |
| `movida-pg-router` | PostgreSQL Router | **Queries, Schema, Calling Services** (`:6446` write / `:6447` read) |
| `movida-pg-primary` | PostgreSQL primary | Vacuum, replication lag |
| `movida-pg-replica` | PostgreSQL replica | Saúde standby |
| `movida-app-alb` | Nginx (ALB HTTP) | LB da camada de aplicação |

Tags de correlação: `db_load_balancer`, `db_router`, `db_cluster`, `db_node`.

Personalize em `.env`: `DD_SERVICE_PG_LB`, `DD_SERVICE_PG_ROUTER`, `DD_SERVICE_PG_PRIMARY`, etc.

---

## O que observar no Datadog

### APM (aplicação Node.js)

- **Service:** `movida-reservas-api`
- **Env:** `movida-lab` (configurável via `DD_ENV`)
- Spans de Express + queries `pg` com propagação DBM (`dbmPropagationMode: full`)

### Database Monitoring (DBM)

| Onde no DBM (us5) | Host | O que ver |
|-------------------|------|-----------|
| LB externo | **movida-pg-haproxy** | Camada NLB (entrada da app) |
| **Queries, Schema, Calling Services** | **movida-pg-router** | Router escrita `:6446` |
| Router leitura | **movida-pg-router-read** | Router leitura `:6447` |
| Vacuums / replication | **movida-pg-primary** | Nó writer |
| Standby | **movida-pg-replica** | Réplica |
- Em **APM → Traces**, use **View in DBM** no host do load balancer

### Schema Explorer + Calling Services

| Recurso | Requisito | Onde ver |
|---------|-----------|----------|
| **Schema** | Agent **7.54+** + `collect_schemas` no router | DBM → **movida-pg-router** |
| **Calling Services** | `PGHOST=haproxy-db` + DBM em **movida-pg-router** (`:6446`) | Propagação APM `full` |

> **Fluxo:** `APP → haproxy-db → pg-router:6446 → pg-primary`. O DBM monitora cada camada com UST distinto.

> **Nota:** Em produção Movida o router pode ser [SPQR](https://www.postgresql.org/about/news/stateless-postgres-query-router-100-released-2759/), PgBouncer ou MySQL Router equivalente; no lab usamos HAProxy nas portas **6446/6447**.

Após `git pull` e rebuild:

```bash
./scripts/compose.sh up -d --build api-1 api-2 datadog-agent
./scripts/verify-dbm-apm-link.sh
```

Calling Services **não aparece na replica** — a API conecta só no primary via HAProxy:5432.

### Integração PostgreSQL

Checks em `datadog/conf.d/postgres.d/conf.yaml` com `dbm: true` para primary e replica.

### Infraestrutura / Containers

- Agent com autodiscovery Docker (`/var/run/docker.sock`)
- Logs das apps e do PostgreSQL via labels `com.datadoghq.ad.logs`

### Dashboards sugeridos (criar no Datadog)

1. **Movida - API via ALB:** latência p95 `trace.express.request`, throughput, taxa de erro 5xx
2. **Movida - PostgreSQL Cluster:** `postgresql.connections`, `postgresql.replication_delay`, CPU dos containers `pg-*`
3. **Movida - Correlação:** APM ↔ DB — use **Trace DB** para ver queries lentas por endpoint

---

## Variáveis de ambiente

Copie `.env.example` para `.env`:

| Variável | Descrição |
|----------|-----------|
| `DD_API_KEY` | **Obrigatória** — chave da organização Datadog |
| `DD_SITE` | Tenant **us5** (default: `us5.datadoghq.com`) |
| `DD_SERVICE_PG_LB` | Nome UST do load balancer PostgreSQL (default: `movida-pg-haproxy`) |
| `DD_SERVICE_PG_PRIMARY` | Nome UST do nó primary |
| `DD_SERVICE_PG_REPLICA` | Nome UST do nó replica |
| `DD_ENV` | Tag de ambiente (ex: `movida-lab`) |
| `APP_ALB_PORT` | Porta HTTP exposta (default 8080) |
| `DB_LB_PORT` | Porta write PostgreSQL via HAProxy |

---

## Comandos úteis

```bash
# Sempre preferir o wrapper (evita erro "docker: unknown command: compose")
./scripts/compose.sh up -d --build

# Rebuild apenas das APIs
./scripts/compose.sh up -d --build api-1 api-2

# Logs do primary
./scripts/compose.sh logs -f pg-primary

# Entrar no primary
docker exec -it pg-primary psql -U postgres -d movida

# Verificar replicação
docker exec -it pg-primary psql -U postgres -c "SELECT * FROM pg_stat_replication;"

# Parar tudo
./scripts/compose.sh down

# Parar e apagar volumes (reset completo)
./scripts/compose.sh down -v
```

---

## Mapeamento para produção AWS (Movida)

| Lab (Docker) | Produção AWS |
|--------------|--------------|
| `alb-app` | ALB → Target Group (ECS/EC2/EKS) |
| `haproxy-db` | NLB ou RDS Proxy / Route53 + endpoints |
| `pg-primary/replica` | Aurora PostgreSQL, RDS Multi-AZ, ou Patroni |
| `datadog-agent` | Agent EC2, ECS sidecar, ou Operator K8s |

Para demo com **ALB real da AWS** apontando para a EC2:

1. Target Group HTTP porta **8080**, health check `/health`
2. Regras de Security Group: ALB → EC2:8080
3. Manter PostgreSQL **sem exposição pública**; apps conectam via endpoint interno

---

## Estrutura do repositório

```text
.
├── app/                    # API Node.js + dd-trace
├── postgres/
│   ├── primary/init/       # Usuários, replication, grants
│   └── replica/            # Standby via pg_basebackup
├── haproxy/                # Load balancer TCP PostgreSQL
├── nginx/                  # ALB HTTP das APIs
├── datadog/                # Agent + check PostgreSQL
├── scripts/
│   ├── ec2-bootstrap.sh
│   └── smoke-test.sh
├── docker-compose.yml
├── .env.example
└── README.md
```

---

## Troubleshooting

| Sintoma | Ação |
|---------|------|
| `ERRO: Docker Compose nao encontrado` | Rode `./scripts/install-docker-compose.sh` ou apenas `./scripts/compose.sh` (baixa o binário em `bin/` na 1ª execução) |
| Tela de help do `docker` (sem subcomando) | Não use `docker compose` direto; use sempre `./scripts/compose.sh` |
| `api-*` em restart loop | Aguarde `pg-primary` healthy; verifique `./scripts/compose.sh logs haproxy-db` |
| Replica não sobe | `docker compose logs pg-replica` — primeiro boot demora; confira senha `REPLICATION_PASSWORD` |
| APM sem traces | Confirme `DD_API_KEY`, porta 8126, `DD_AGENT_HOST=datadog-agent` nos containers api |
| Postgres check NO DATA | Verifique usuário/senha em `.env` e conectividade agent → `pg-primary` |
| DBM: `pg_stat_statements is not created` | Rode `git pull && ./scripts/enable-pg-stat-statements.sh` ou recrie volumes com `./scripts/compose.sh down -v` |
| DBM replica: `pg_stat_statements not loaded` | Replica precisa de `--build` (`enable-pg-stat-statements.sh` ja faz). Valide: `docker exec pg-replica psql -U postgres -d movida -c "SHOW shared_preload_libraries;"` |
| DBM primary: `Unable to fetch wraparound data` | Geralmente benigno em lab/demo; grants `pg_monitor` no init. Atualize após 15 min ou ignore se Queries/APM estiverem OK |

---

## Licença

Projeto de demonstração técnica para workshops Datadog / cenário Movida.
