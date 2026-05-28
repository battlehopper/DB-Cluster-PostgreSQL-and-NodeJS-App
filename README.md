# DB-Cluster-PostgreSQL-and-NodeJS-App

Container project for monitoring on Datadog. Laboratório que reproduz o cenário **Movida**: aplicações **Node.js** conectando a um **cluster PostgreSQL** através de camada de **load balancing** (simulando **ALB/NLB** na AWS), com observabilidade completa no **Datadog** via **Datadog Agent**.

Repositório: [github.com/battlehopper/DB-Cluster-PostgreSQL-and-NodeJS-App](https://github.com/battlehopper/DB-Cluster-PostgreSQL-and-NodeJS-App)

---

## Arquitetura

```text
                         ┌─────────────────────┐
                         │   Datadog Agent     │
                         │ APM + Logs + PG DB  │
                         └──────────┬──────────┘
                                    │ coleta
┌──────────────┐    HTTP :8080      │      ┌─────────────┐
│   Cliente    │ ───────────────►   │      │  api-1      │
│  (curl/ALB)  │      alb-app       ├─────►│  api-2      │
└──────────────┘    (nginx ALB)     │      └──────┬──────┘
                                    │             │ PG via haproxy-db:5432
                                    │      ┌──────▼──────┐
                                    │      │ haproxy-db  │  ← NLB/ALB TCP (PostgreSQL)
                                    │      └──────┬──────┘
                                    │    ┌────────┴────────┐
                                    │    │                 │
                                    │ pg-primary      pg-replica
                                    │  (write)         (read standby)
```

| Componente | Papel no lab | Equivalente AWS (cliente Movida) |
|------------|--------------|----------------------------------|
| `alb-app` (nginx) | Balanceamento HTTP das APIs | **Application Load Balancer** |
| `haproxy-db` | Endpoint único PostgreSQL (write/read) | **NLB** ou proxy TCP na frente do cluster |
| `pg-primary` / `pg-replica` | Cluster com replicação streaming | RDS/Aurora PostgreSQL ou EC2 cluster |
| `api-1` / `api-2` | Microserviços Node.js | ECS/EKS/EC2 apps |
| `datadog-agent` | Métricas, logs, APM, checks PostgreSQL | Agent na EC2 ou DaemonSet |

> **Nota:** ALB real é camada 7 (HTTP). Para PostgreSQL em produção costuma-se usar **NLB**, **RDS Proxy** ou **PgBouncer**. Neste lab, `haproxy-db` representa o **endpoint único** que as apps usam para falar com o cluster — o padrão observado em clientes enterprise.

---

## Stack de containers

| Container | Imagem | Porta (host) |
|-----------|--------|--------------|
| `pg-primary` | postgres:16-alpine | interna |
| `pg-replica` | build local | interna |
| `haproxy-db` | haproxy:2.9 | 5432 (write), 5433 (read) |
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
docker compose up -d --build
docker compose ps
docker compose logs -f --tail=50
```

A replica pode levar **1–2 minutos** no primeiro `pg_basebackup`.

### 5. Validar

```bash
./scripts/smoke-test.sh
# ou manualmente:
curl http://$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4):8080/health
```

### 6. (Opcional) Gerar tráfego contínuo

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

## O que observar no Datadog

### APM (aplicação Node.js)

- **Service:** `movida-reservas-api`
- **Env:** `movida-lab` (configurável via `DD_ENV`)
- Spans de Express + queries `pg` instrumentadas pelo `dd-trace`

### Integração PostgreSQL

Checks configurados em `datadog/conf.d/postgres.d/conf.yaml` para:

- `pg-primary` (role: primary)
- `pg-replica` (role: replica)

Métricas úteis: conexões, deadlocks, replication lag, tamanho de tabelas.

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
| `DD_ENV` | Tag de ambiente (ex: `movida-lab`) |
| `APP_ALB_PORT` | Porta HTTP exposta (default 8080) |
| `DB_LB_PORT` | Porta write PostgreSQL via HAProxy |

---

## Comandos úteis

```bash
# Rebuild apenas das APIs
docker compose up -d --build api-1 api-2

# Logs do primary
docker compose logs -f pg-primary

# Entrar no primary
docker exec -it pg-primary psql -U postgres -d movida

# Verificar replicação
docker exec -it pg-primary psql -U postgres -c "SELECT * FROM pg_stat_replication;"

# Parar tudo
docker compose down

# Parar e apagar volumes (reset completo)
docker compose down -v
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
| `api-*` em restart loop | Aguarde `pg-primary` healthy; verifique `docker compose logs haproxy-db` |
| Replica não sobe | `docker compose logs pg-replica` — primeiro boot demora; confira senha `REPLICATION_PASSWORD` |
| APM sem traces | Confirme `DD_API_KEY`, porta 8126, `DD_AGENT_HOST=datadog-agent` nos containers api |
| Postgres check NO DATA | Verifique usuário/senha em `.env` e conectividade agent → `pg-primary` |

---

## Licença

Projeto de demonstração técnica para workshops Datadog / cenário Movida.
