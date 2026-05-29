# Passo a passo — Movida: DBM + UST em cluster PostgreSQL via Load Balancer

Guia para implementar no ambiente **Movida** o mesmo conceito do lab: aplicações Node.js conectando ao PostgreSQL **via endpoint de load balancing**, com **Database Monitoring (DBM)** e **Unified Service Tagging (UST)** no Datadog.

Referências:
- [Unified Service Tagging](https://docs.datadoghq.com/getting_started/tagging/unified_service_tagging/?tab=docker)
- [DBM PostgreSQL self-hosted](https://docs.datadoghq.com/database_monitoring/setup_postgres/selfhosted/)
- [Correlacionar DBM e APM](https://docs.datadoghq.com/database_monitoring/connect_dbm_and_apm/?tab=nodejs)

---

## 1. Arquitetura alvo (produção Movida)

```text
                    ┌─────────────────────────────────────┐
                    │         Datadog (tenant us5)          │
                    │   DBM + APM + Logs + Infra            │
                    └──────────────────┬──────────────────┘
                                       │
┌──────────────┐   HTTP    ┌───────────▼──────────┐
│   Clientes   │ ────────► │  ALB (aplicações)     │
└──────────────┘           └───────────┬──────────┘
                                       │
                              ┌────────▼────────┐
                              │  ECS/EKS/EC2    │
                              │  movida-*-api   │  DD_SERVICE=movida-reservas-api
                              └────────┬────────┘
                                       │ PGHOST = endpoint do LB/proxy
                              ┌────────▼────────────────────────┐
                              │  NLB / RDS Proxy / Route53      │
                              │  movida-pg-haproxy (UST)        │
                              └────────┬────────────────────────┘
                         ┌─────────────┴─────────────┐
                         │                           │
                  ┌──────▼──────┐            ┌───────▼───────┐
                  │  Primary    │  WAL       │  Replica(s)   │
                  │  writer     │ ─────────► │  reader       │
                  └─────────────┘            └───────────────┘
```

| Lab (Docker) | Produção Movida (exemplos) |
|--------------|----------------------------|
| `alb-app` (nginx) | **ALB** → Target Group das APIs |
| `haproxy-db` | **NLB**, **RDS Proxy**, **PgBouncer** ou DNS do cluster |
| `pg-primary` / `pg-replica` | Aurora/RDS Multi-AZ, Patroni, EC2 cluster |
| `datadog-agent` (container) | Agent EC2, sidecar ECS, DaemonSet EKS |

> **Importante:** a aplicação **nunca** deve usar o hostname interno do nó writer (`pg-primary`). Deve usar o **endpoint unificado** do balanceador/proxy — igual ao `PGHOST=haproxy-db` do lab.

---

## 2. Pré-requisitos

### 2.1 PostgreSQL (todos os nós writer + replicas)

- PostgreSQL **12+** (recomendado 14+)
- Extensão **`pg_stat_statements`** habilitada
- Usuário de monitoramento com permissões adequadas

```sql
-- Executar no PRIMARY (replica herda extensão via catálogo)
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

-- Usuário dedicado Datadog (recomendado; evitar superuser em prod)
CREATE USER datadog WITH PASSWORD '<senha_forte>';
GRANT pg_monitor TO datadog;
GRANT SELECT ON pg_stat_statements TO datadog;
GRANT pg_read_all_settings TO datadog;

-- Permissões no banco da aplicação
GRANT CONNECT ON DATABASE movida TO datadog;
GRANT USAGE ON SCHEMA public TO datadog;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO datadog;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO datadog;
```

No `postgresql.conf` (ou parameter group RDS/Aurora):

```ini
shared_preload_libraries = 'pg_stat_statements'
pg_stat_statements.track = all
pg_stat_statements.max = 10000
track_activity_query_size = 4096
```

Reinicie o PostgreSQL após alterar `shared_preload_libraries`.

### 2.2 Datadog

- Agent **≥ 7.54** (Schema Explorer) — recomendado **7.60+**
- Integração **PostgreSQL** + **DBM** habilitados
- **APM** habilitado nas APIs Node.js
- Tenant: `us5.datadoghq.com`

### 2.3 Aplicação Node.js

- `dd-trace` **≥ 3.17.0** (recomendado 5.x)
- Driver `pg` com suporte a `queryMode: 'simple'` (propagação DBM)

---

## 3. Definir a convenção UST (antes de instalar)

Padronize **uma vez** com o time de plataforma:

| Tag | Valor Movida (exemplo) | Onde aplicar |
|-----|------------------------|--------------|
| `env` | `production`, `staging`, `homolog` | Todos os serviços |
| `version` | `2025.05.1` ou git SHA | Deploy de cada release |
| `service` (API) | `movida-reservas-api` | ECS task / K8s pod / PM2 |
| `service` (LB DB) | `movida-pg-haproxy` | Check DBM do endpoint |
| `service` (primary) | `movida-pg-primary` | Check DBM do nó writer |
| `service` (replica) | `movida-pg-replica` | Check DBM de cada réplica |

Tags custom de cluster (complementares ao UST):

```text
cluster:movida-pg
db_cluster:movida-pg
db_load_balancer:movida-pg-haproxy
db_node:primary | replica
db_role:writer | reader | load_balancer_endpoint
```

---

## 4. Instalar e configurar o Datadog Agent

### 4.1 ECS (task definition) — variáveis UST + DBM

```json
"environment": [
  { "name": "DD_API_KEY", "value": "<API_KEY>" },
  { "name": "DD_SITE", "value": "us5.datadoghq.com" },
  { "name": "DD_ENV", "value": "production" },
  { "name": "DD_VERSION", "value": "2025.05.1" },
  { "name": "DD_DBM_ENABLED", "value": "true" },
  { "name": "DD_APM_ENABLED", "value": "true" },
  { "name": "DD_LOGS_ENABLED", "value": "true" },
  { "name": "DD_SERVICE_PG_LB", "value": "movida-pg-haproxy" },
  { "name": "DD_SERVICE_PG_PRIMARY", "value": "movida-pg-primary" },
  { "name": "DD_SERVICE_PG_REPLICA", "value": "movida-pg-replica" },
  { "name": "POSTGRES_USER", "value": "datadog" },
  { "name": "POSTGRES_PASSWORD", "value": "<SECRET>" }
],
"dockerLabels": {
  "com.datadoghq.tags.env": "production",
  "com.datadoghq.tags.service": "datadog-agent",
  "com.datadoghq.tags.version": "2025.05.1"
}
```

### 4.2 Check PostgreSQL — 3 instâncias (mesmo modelo do lab)

Arquivo: `/etc/datadog-agent/conf.d/postgres.d/conf.yaml`

```yaml
init_config:

instances:
  # ── ENDPOINT DA APLICAÇÃO (NLB / RDS Proxy / PgBouncer) ──
  - host: <dns-do-endpoint-lb>.movida.internal   # ex: pg-cluster.movida.internal
    port: 5432
    username: "%%env_POSTGRES_USER%%"
    password: "%%env_POSTGRES_PASSWORD%%"
    dbname: movida
    reported_hostname: "%%env_DD_SERVICE_PG_LB%%"   # movida-pg-haproxy
    dbm: true
    collect_schemas:
      enabled: true
    tags:
      - "env:%%env_DD_ENV%%"
      - "service:%%env_DD_SERVICE_PG_LB%%"
      - "version:%%env_DD_VERSION%%"
      - "cluster:movida-pg"
      - "db_cluster:movida-pg"
      - "db_role:load_balancer_endpoint"
      - "db_load_balancer:%%env_DD_SERVICE_PG_LB%%"
    relations:
      - relation_regex: '.*'
        relkind: [r, i]

  # ── NÓ PRIMARY (writer) ──
  - host: <hostname-interno-primary>              # ex: pg-primary.movida.internal
    port: 5432
    username: "%%env_POSTGRES_USER%%"
    password: "%%env_POSTGRES_PASSWORD%%"
    dbname: movida
    reported_hostname: movida-pg-primary
    dbm: true
    query_metrics:
      enabled: false          # evita duplicar queries do endpoint LB
    query_samples:
      enabled: false
    collect_schemas:
      enabled: false
    relations:
      - relation_regex: '.*'
        relkind: [r, i]
    tags:
      - "env:%%env_DD_ENV%%"
      - "service:%%env_DD_SERVICE_PG_PRIMARY%%"
      - "version:%%env_DD_VERSION%%"
      - "cluster:movida-pg"
      - "db_node:primary"
      - "db_role:writer"
      - "db_load_balancer:%%env_DD_SERVICE_PG_LB%%"
    custom_queries:
      - metric_suffix: replication.lag_bytes
        query: >
          SELECT COALESCE(
            pg_wal_lsn_diff(pg_current_wal_lsn(), replay_lsn), 0
          ) AS lag FROM pg_stat_replication LIMIT 1;
        columns:
          - { name: lag, type: gauge }

  # ── NÓ REPLICA (standby) — repetir por réplica ──
  - host: <hostname-interno-replica-1>
    port: 5432
    username: "%%env_POSTGRES_USER%%"
    password: "%%env_POSTGRES_PASSWORD%%"
    dbname: movida
    reported_hostname: movida-pg-replica
    dbm: false
    tags:
      - "env:%%env_DD_ENV%%"
      - "service:%%env_DD_SERVICE_PG_REPLICA%%"
      - "version:%%env_DD_VERSION%%"
      - "cluster:movida-pg"
      - "db_node:replica"
      - "db_role:reader"
      - "db_load_balancer:%%env_DD_SERVICE_PG_LB%%"
```

Reinicie o Agent:

```bash
sudo systemctl restart datadog-agent
sudo datadog-agent status | grep -A5 postgres
```

---

## 5. Configurar a aplicação Node.js

### 5.1 Variáveis de ambiente (ECS / K8s / .env)

```bash
# UST
DD_ENV=production
DD_SERVICE=movida-reservas-api
DD_VERSION=2025.05.1
DD_SITE=us5.datadoghq.com

# APM + DBM
DD_AGENT_HOST=<ip-do-agent-ou-service>
DD_DBM_PROPAGATION_MODE=full
DD_LOGS_INJECTION=true

# Banco — SEMPRE o endpoint do LB/proxy, NUNCA o hostname do primary
PGHOST=pg-cluster.movida.internal    # = DNS do NLB/RDS Proxy
PGPORT=5432
PGDATABASE=movida
PGUSER=movida_app
PGPASSWORD=<secret>
```

### 5.2 Labels Docker / ECS (UST nos containers)

```json
"dockerLabels": {
  "com.datadoghq.tags.env": "production",
  "com.datadoghq.tags.service": "movida-reservas-api",
  "com.datadoghq.tags.version": "2025.05.1"
}
```

### 5.3 Código — tracer + propagação DBM

```javascript
// tracing.js — PRIMEIRO import da aplicação
const tracer = require('dd-trace').init({
  env: process.env.DD_ENV,
  service: process.env.DD_SERVICE,
  version: process.env.DD_VERSION,
  logInjection: true,
  dbmPropagationMode: 'full',
});

tracer.use('pg', {
  dbmPropagationMode: 'full',
});

module.exports = tracer;
```

```javascript
// db.js — protocolo simples para comentários DBM no SQL
require('./tracing');
const { Pool } = require('pg');

const pool = new Pool({ host: process.env.PGHOST, /* ... */ });

const originalQuery = pool.query.bind(pool);
pool.query = (text, values, cb) => {
  const q = typeof text === 'string'
    ? { text, values, queryMode: 'simple' }
    : { ...text, queryMode: text.queryMode || 'simple' };
  return typeof cb === 'function' ? originalQuery(q, cb) : originalQuery(q);
};
```

---

## 6. UST nos demais componentes

| Componente | `DD_ENV` | `DD_SERVICE` | Labels Docker |
|------------|----------|--------------|---------------|
| API Node.js | `production` | `movida-reservas-api` | env + service + version |
| ALB (app) | — | — | métricas AWS via integração |
| NLB/Proxy DB | — | `movida-pg-haproxy` | via check postgres |
| Primary | — | `movida-pg-primary` | via check postgres |
| Replica | — | `movida-pg-replica` | via check postgres |

---

## 7. Validação (checklist)

### 7.1 PostgreSQL

```sql
-- No primary
SHOW shared_preload_libraries;          -- deve listar pg_stat_statements
SELECT count(*) FROM pg_stat_statements; -- > 0 após tráfego
SELECT * FROM pg_stat_replication;       -- réplicas conectadas
```

### 7.2 Agent

```bash
datadog-agent status
# Verificar: postgres check OK, DBM enabled, 3 instances
```

### 7.3 Datadog UI (us5) — após 10–15 min de tráfego

| Verificação | Onde | Esperado |
|-------------|------|----------|
| Setup Issues = 0 | DBM → Setup | Sem erros pg_stat_statements |
| Cluster agrupado | DBM → Databases | `cluster:movida-pg` |
| Queries | **movida-pg-haproxy** | Top SQL da aplicação |
| Schema | **movida-pg-haproxy** | Tabelas do banco `movida` |
| Calling Services | **movida-pg-haproxy** ou **movida-pg-primary** | `movida-reservas-api` |
| Vacuums | **movida-pg-primary** | Dados de autovacuum |
| Replication lag | **movida-pg-primary** | Métrica custom |
| APM ↔ DBM | Trace → View in DBM | Query correlacionada |
| Replica | **movida-pg-replica** | Sem Calling Services (normal) |

### 7.4 Facets UST no DBM

Filtros que devem aparecer:

- `env:production`
- `service:movida-pg-haproxy`
- `service:movida-pg-primary`
- `service:movida-pg-replica`
- `db_load_balancer:movida-pg-haproxy`
- `db_node:primary` / `db_node:replica`

---

## 8. Ordem de implementação recomendada

```text
Semana 1 — Fundação
  □ Habilitar pg_stat_statements no cluster
  □ Criar usuário datadog + grants
  □ Instalar Agent com DD_DBM_ENABLED=true
  □ Definir convenção UST (env/service/version)

Semana 2 — DBM
  □ Configurar 3 instâncias postgres.d (LB + primary + replica)
  □ Validar Setup Issues = 0
  □ Confirmar cluster:movida-pg no UI

Semana 3 — APM + Correlação
  □ Instrumentar APIs com dd-trace + UST labels
  □ PGHOST = endpoint do LB
  □ DD_DBM_PROPAGATION_MODE=full + queryMode simple
  □ Validar Calling Services

Semana 4 — Operacional
  □ Dashboards: API (ALB) + DBM (cluster) + correlação
  □ Monitors: replication lag, conexões, query latency
  □ Runbook para novas réplicas (copiar bloco replica do conf.yaml)
```

---

## 9. RDS / Aurora (variações Movida)

### Amazon RDS / Aurora PostgreSQL

- `pg_stat_statements` via **Parameter Group** (`shared_preload_libraries`)
- Agent conecta nos endpoints:
  - **Cluster endpoint** (writer) → mapear como `movida-pg-haproxy` se apps usam cluster endpoint
  - **Reader endpoint** → check separado para réplicas
  - **RDS Proxy endpoint** → check do LB (`movida-pg-haproxy`)

### RDS Proxy

- Apps: `PGHOST = <proxy-endpoint>.rds.amazonaws.com`
- DBM check LB: `host: <proxy-endpoint>`
- Checks de nós: endpoints individuais das instâncias RDS (writer/readers)

---

## 10. Troubleshooting rápido

| Sintoma | Causa provável | Ação |
|---------|----------------|------|
| `pg_stat_statements not created` | Extensão ausente | `CREATE EXTENSION` + restart |
| `pg_stat_statements not loaded` (replica) | preload ausente na réplica | Parameter group + restart replica |
| Calling Services vazio | Propagação APM off ou PGHOST errado | `DD_DBM_PROPAGATION_MODE=full`, `tracer.use('pg')` |
| Schema vazio | Agent < 7.54 ou `collect_schemas` off | Atualizar Agent + conf |
| Queries duplicadas | dbm true em LB e primary | `query_metrics: false` no primary |
| Vacuum sumiu | dbm false no primary | dbm true + query_metrics false |

---

## 11. Referência — repositório do lab

Implementação de referência completa:

**https://github.com/battlehopper/DB-Cluster-PostgreSQL-and-NodeJS-App**

Arquivos-chave:

| Arquivo | Conteúdo |
|---------|----------|
| `datadog/conf.d/postgres.d/conf.yaml` | 3 instâncias DBM + UST |
| `docker-compose.yml` | UST labels + env vars |
| `app/src/tracing.js` | Propagação APM→DBM |
| `app/src/db.js` | queryMode simple + PGHOST via LB |
| `.env.example` | Nomes UST centralizados |
