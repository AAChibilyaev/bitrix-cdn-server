# 🚀 CI/CD Pipeline и GitHub Actions

**Автор**: Chibilyaev Alexandr | **AAChibilyaev LTD** | info@aachibilyaev.com

## 🔄 GitHub Actions Workflow

```mermaid
flowchart TD
    subgraph "💻 Development Process"
        DEV[👨‍💻 Developer<br/>Local Development]
        COMMIT[📝 Git Commit<br/>Feature Branch]
        PUSH[📤 Git Push<br/>to GitHub]
        PR[🔄 Pull Request<br/>to main branch]
    end
    
    subgraph "🤖 GitHub Actions - CI Pipeline"
        TRIGGER[⚡ Workflow Trigger<br/>Push/PR Event]
        
        subgraph "🔍 Code Quality Checks"
            LINT[📋 Lint Check<br/>shellcheck, yamllint<br/>hadolint (Dockerfile)]
            SECURITY[🔒 Security Scan<br/>trivy, bandit<br/>dependency check]
            SYNTAX[✅ Syntax Validation<br/>nginx -t, compose config]
        end
        
        subgraph "🐳 Docker Build & Test"
            BUILD[🏗️ Docker Build<br/>Multi-stage builds<br/>Layer caching]
            UNIT_TEST[🧪 Unit Tests<br/>Python converter<br/>Bash script tests]
            INTEGRATION[🔗 Integration Test<br/>Container connectivity<br/>Health checks]
        end
        
        subgraph "📊 Performance & Security"
            PERF_TEST[⚡ Performance Test<br/>WebP conversion speed<br/>Memory usage checks]
            VULN_SCAN[🛡️ Vulnerability Scan<br/>Container images<br/>Dependencies]
            CONFIG_TEST[⚙️ Config Validation<br/>NGINX, Prometheus<br/>Redis, Grafana]
        end
    end
    
    subgraph "🎯 Deployment Environments"
        DEV_ENV[🧪 Development<br/>Auto-deploy on develop<br/>cdn-dev.termokit.ru]
        STAGING[🚧 Staging<br/>Manual approval<br/>cdn-staging.termokit.ru]
        PRODUCTION[🌟 Production<br/>Manual approval<br/>cdn.termokit.ru]
    end
    
    %% Development flow
    DEV --> COMMIT
    COMMIT --> PUSH
    PUSH --> TRIGGER
    
    %% CI Pipeline
    TRIGGER --> LINT
    TRIGGER --> SECURITY
    TRIGGER --> SYNTAX
    
    LINT --> BUILD
    SECURITY --> BUILD  
    SYNTAX --> BUILD
    
    BUILD --> UNIT_TEST
    UNIT_TEST --> INTEGRATION
    INTEGRATION --> PERF_TEST
    PERF_TEST --> VULN_SCAN
    VULN_SCAN --> CONFIG_TEST
    
    %% Deployment flow
    CONFIG_TEST --> DEV_ENV
    DEV_ENV --> PR
    PR --> STAGING
    STAGING --> PRODUCTION
    
    %% Success paths
    PRODUCTION --> SUCCESS[✅ Deployment Complete<br/>Monitoring Active]
    
    %% Failure paths
    LINT -.->|❌ Fail| FAIL[❌ Pipeline Failed<br/>Fix Issues]
    SECURITY -.->|❌ Fail| FAIL
    BUILD -.->|❌ Fail| FAIL
    INTEGRATION -.->|❌ Fail| FAIL
    VULN_SCAN -.->|❌ Fail| FAIL
    
    FAIL --> DEV

    style DEV fill:#e3f2fd
    style TRIGGER fill:#4caf50
    style BUILD fill:#2196f3
    style PRODUCTION fill:#ff9800
    style SUCCESS fill:#8bc34a
    style FAIL fill:#f44336
```

## 📝 Детальный CI Pipeline

```mermaid
graph TD
    subgraph "🔄 Pull Request Pipeline"
        PR_OPEN[📤 PR Created/Updated]
        
        subgraph "Stage 1: Static Analysis"
            S1_LINT[📋 ShellCheck<br/>Bash scripts validation]
            S1_YAML[📄 YAML Lint<br/>docker-compose validation]
            S1_DOCKER[🐳 Hadolint<br/>Dockerfile best practices]
            S1_NGINX[🌐 NGINX Config Test<br/>nginx -t validation]
        end
        
        subgraph "Stage 2: Security Scanning"
            S2_SECRETS[🔐 Secret Detection<br/>GitLeaks, TruffleHog]
            S2_DEPS[📦 Dependency Scan<br/>npm audit, pip-audit]
            S2_CODE[🛡️ Code Security<br/>bandit (Python), semgrep]
        end
        
        subgraph "Stage 3: Build & Test"
            S3_BUILD[🏗️ Docker Build<br/>All services build test]
            S3_COMPOSE[🐳 Compose Up<br/>Integration test]
            S3_HEALTH[❤️ Health Checks<br/>All services healthy]
            S3_API[🌐 API Tests<br/>WebP conversion test]
        end
        
        subgraph "Stage 4: Performance"
            S4_LOAD[⚡ Load Test<br/>Image conversion stress]
            S4_MEMORY[💾 Memory Test<br/>Resource usage limits]
            S4_DISK[💽 Disk Test<br/>Cache growth simulation]
        end
    end
    
    subgraph "🎯 Deployment Pipeline"
        MERGE[🔄 Merge to Main]
        
        subgraph "Production Deployment"
            DEPLOY_PREP[🎯 Deployment Prep<br/>Tag version<br/>Generate changelog]
            DEPLOY_PROD[🚀 Production Deploy<br/>Zero-downtime<br/>Blue-green strategy]
            DEPLOY_VERIFY[✅ Deployment Verify<br/>Smoke tests<br/>Monitoring checks]
        end
        
        subgraph "Post-deployment"
            MONITOR[👀 Monitoring<br/>Grafana alerts<br/>Performance check]
            ROLLBACK[🔄 Auto Rollback<br/>On failure detection]
            SUCCESS_NOTIFY[📧 Success Notification<br/>Slack/Email alert]
        end
    end
    
    %% Pipeline flow
    PR_OPEN --> S1_LINT
    PR_OPEN --> S1_YAML
    PR_OPEN --> S1_DOCKER
    PR_OPEN --> S1_NGINX
    
    S1_LINT --> S2_SECRETS
    S1_YAML --> S2_DEPS
    S1_DOCKER --> S2_CODE
    S1_NGINX --> S2_SECRETS
    
    S2_SECRETS --> S3_BUILD
    S2_DEPS --> S3_COMPOSE
    S2_CODE --> S3_HEALTH
    
    S3_BUILD --> S3_COMPOSE
    S3_COMPOSE --> S3_HEALTH
    S3_HEALTH --> S3_API
    
    S3_API --> S4_LOAD
    S4_LOAD --> S4_MEMORY
    S4_MEMORY --> S4_DISK
    
    %% Deployment flow
    S4_DISK --> MERGE
    MERGE --> DEPLOY_PREP
    DEPLOY_PREP --> DEPLOY_PROD
    DEPLOY_PROD --> DEPLOY_VERIFY
    
    DEPLOY_VERIFY --> MONITOR
    MONITOR --> SUCCESS_NOTIFY
    
    %% Failure handling
    DEPLOY_VERIFY -.->|❌ Fail| ROLLBACK
    MONITOR -.->|🚨 Alert| ROLLBACK
    ROLLBACK --> DEPLOY_VERIFY

    style PR_OPEN fill:#e3f2fd
    style S3_BUILD fill:#4caf50
    style DEPLOY_PROD fill:#ff9800
    style SUCCESS_NOTIFY fill:#8bc34a
    style ROLLBACK fill:#f44336
```

## 🏗️ Build Process Детализация

```mermaid
sequenceDiagram
    participant Dev as 👨‍💻 Developer
    participant GH as 📱 GitHub
    participant GA as 🤖 GitHub Actions
    participant Docker as 🐳 Docker Hub
    participant Staging as 🚧 Staging Server
    participant Prod as 🌟 Production CDN
    participant Monitor as 📊 Monitoring
    
    Note over Dev,Monitor: Development & Integration Flow
    
    Dev->>GH: git push origin feature-branch
    GH->>GA: Trigger workflow on push
    
    Note over GA: Stage 1: Static Analysis
    GA->>GA: shellcheck scripts/*.sh
    GA->>GA: yamllint docker-compose.yml
    GA->>GA: hadolint docker/*/Dockerfile
    GA->>GA: nginx -t validation
    
    Note over GA: Stage 2: Security
    GA->>GA: trivy fs . (filesystem scan)
    GA->>GA: bandit python scripts
    GA->>GA: Check secrets exposure
    
    Note over GA: Stage 3: Build & Test
    GA->>Docker: docker build (all services)
    GA->>GA: docker-compose up -d
    GA->>GA: Wait for services (60s)
    
    loop Health Check
        GA->>GA: curl nginx/health
        GA->>GA: Check SSHFS mount
        GA->>GA: Test Redis connection
        GA->>GA: Verify WebP conversion
    end
    
    Note over GA: Stage 4: Integration Tests
    GA->>GA: Test image conversion
    GA->>GA: Check cache functionality
    GA->>GA: Verify monitoring endpoints
    
    GA->>GH: ✅ All tests passed
    GH->>Dev: 📧 Notify PR ready
    
    Note over Dev,Prod: Deployment Flow
    
    Dev->>GH: Merge PR to main
    GH->>GA: Trigger deployment workflow
    
    GA->>Staging: Deploy to staging
    Staging->>Monitor: Health check
    Monitor->>GA: ✅ Staging healthy
    
    GA->>GH: 📋 Manual approval required
    Dev->>GH: ✅ Approve production deploy
    
    GA->>Prod: Blue-green deployment
    Prod->>Monitor: Health verification
    
    alt Deployment Success
        Monitor->>GA: ✅ Production healthy
        GA->>Dev: 📧 Success notification
    else Deployment Failure
        Monitor->>GA: ❌ Health check failed
        GA->>Prod: 🔄 Auto rollback
        GA->>Dev: 🚨 Failure notification
    end
```

## 🧪 Testing Strategy

```mermaid
graph TB
    subgraph "🔬 Test Pyramid"
        subgraph "Unit Tests (Fast)"
            UT_PYTHON[🐍 Python Tests<br/>WebP converter logic<br/>File handling<br/>Error cases]
            UT_BASH[💻 Bash Tests<br/>Script validation<br/>Parameter handling<br/>Edge cases]
            UT_CONFIG[⚙️ Config Tests<br/>NGINX syntax<br/>Docker compose<br/>Environment vars]
        end
        
        subgraph "Integration Tests (Medium)"
            IT_SERVICES[🔗 Service Integration<br/>Container communication<br/>Volume mounting<br/>Network connectivity]
            IT_API[🌐 API Integration<br/>HTTP endpoint tests<br/>WebP conversion flow<br/>Cache behavior]
            IT_HEALTH[❤️ Health Integration<br/>Service dependencies<br/>Startup sequence<br/>Failure recovery]
        end
        
        subgraph "End-to-End Tests (Slow)"
            E2E_USER[👤 User Journey<br/>Full request flow<br/>Image conversion<br/>Cache performance]
            E2E_MONITOR[📊 Monitoring E2E<br/>Metrics collection<br/>Alert generation<br/>Dashboard updates]
            E2E_DEPLOY[🚀 Deployment E2E<br/>Zero-downtime deploy<br/>Rollback testing<br/>Data persistence]
        end
    end
    
    subgraph "🎯 Test Execution Strategy"
        PARALLEL[⚡ Parallel Execution<br/>Unit + Config tests<br/>Fast feedback]
        
        SEQUENTIAL[🔄 Sequential Flow<br/>Integration → E2E<br/>Resource management]
        
        CONDITIONAL[🎛️ Conditional Tests<br/>Performance (on schedule)<br/>Load (on release)]
    end
    
    subgraph "📈 Test Coverage Goals"
        COVERAGE[📊 Coverage Targets<br/>Unit: >90%<br/>Integration: >80%<br/>E2E: Key flows]
        
        QUALITY[🏆 Quality Gates<br/>No critical security issues<br/>All health checks pass<br/>Performance benchmarks met]
    end
    
    %% Test flow
    UT_PYTHON --> PARALLEL
    UT_BASH --> PARALLEL
    UT_CONFIG --> PARALLEL
    
    PARALLEL --> IT_SERVICES
    IT_SERVICES --> IT_API
    IT_API --> IT_HEALTH
    
    IT_HEALTH --> SEQUENTIAL
    SEQUENTIAL --> E2E_USER
    E2E_USER --> E2E_MONITOR
    E2E_MONITOR --> E2E_DEPLOY
    
    E2E_DEPLOY --> CONDITIONAL
    CONDITIONAL --> COVERAGE
    COVERAGE --> QUALITY

    style UT_PYTHON fill:#4caf50
    style IT_SERVICES fill:#2196f3
    style E2E_USER fill:#ff9800
    style QUALITY fill:#9c27b0
    style PARALLEL fill:#8bc34a
```

## 🔧 Deployment Environments

```mermaid
graph LR
    subgraph "🌍 Environment Hierarchy"
        subgraph "Development"
            DEV_LOCAL[💻 Local Dev<br/>docker-compose.dev.yml<br/>No SSL<br/>Mock data]
            DEV_BRANCH[🌱 Feature Branches<br/>Automatic deploy<br/>cdn-dev.termokit.ru<br/>Self-signed SSL]
        end
        
        subgraph "Testing"
            STAGING[🚧 Staging<br/>Production mirror<br/>cdn-staging.termokit.ru<br/>Let's Encrypt SSL]
            QA[🔍 QA Environment<br/>Manual testing<br/>Load testing<br/>Security testing]
        end
        
        subgraph "Production"
            PROD_BLUE[🔵 Blue Environment<br/>cdn.termokit.ru<br/>Active traffic]
            PROD_GREEN[🟢 Green Environment<br/>cdn.termokit.ru<br/>Standby/Deploy target]
        end
    end
    
    subgraph "🔀 Traffic Management"
        LB[⚖️ Load Balancer<br/>CloudFlare/AWS<br/>Health-based routing]
        DNS[🌐 DNS Management<br/>A/AAAA records<br/>Failover logic]
        CDN[🚀 CDN Layer<br/>Global cache<br/>Edge locations]
    end
    
    subgraph "📊 Monitoring per Environment"
        METRICS[📈 Environment Metrics<br/>Separate Grafana<br/>Environment tags]
        ALERTS[🚨 Environment Alerts<br/>Different thresholds<br/>Escalation paths]
        LOGS[📋 Centralized Logging<br/>ELK/Loki stack<br/>Environment filtering]
    end
    
    %% Flow between environments
    DEV_LOCAL --> DEV_BRANCH
    DEV_BRANCH --> STAGING
    STAGING --> QA
    QA --> PROD_GREEN
    PROD_GREEN --> PROD_BLUE
    
    %% Traffic routing
    LB --> PROD_BLUE
    LB -.->|Rollback| PROD_GREEN
    DNS --> LB
    CDN --> DNS
    
    %% Monitoring integration
    DEV_BRANCH --> METRICS
    STAGING --> METRICS
    PROD_BLUE --> METRICS
    PROD_GREEN --> METRICS
    
    METRICS --> ALERTS
    ALERTS --> LOGS

    style DEV_LOCAL fill:#e8f5e8
    style STAGING fill:#fff3e0
    style PROD_BLUE fill:#e3f2fd
    style PROD_GREEN fill:#f3e5f5
    style LB fill:#ff9800
    style ALERTS fill:#f44336
```

## 🎛️ Release Management

```mermaid
gitGraph
    commit id: "v1.0.0"
    
    branch develop
    checkout develop
    commit id: "feature: monitoring"
    commit id: "fix: nginx config"
    
    branch feature/webp-optimization
    checkout feature/webp-optimization
    commit id: "optimize: webp quality"
    commit id: "test: conversion tests"
    
    checkout develop
    merge feature/webp-optimization
    commit id: "merge: webp optimization"
    
    checkout main
    merge develop
    commit id: "release: v1.1.0"
    commit id: "hotfix: security patch"
    commit id: "v1.1.1"
    
    checkout develop
    merge main
    commit id: "sync: develop with main"
    
    branch feature/redis-clustering
    checkout feature/redis-clustering
    commit id: "add: redis cluster"
    commit id: "config: cluster setup"
    
    checkout develop
    merge feature/redis-clustering
    
    checkout main
    merge develop
    commit id: "release: v1.2.0"
```

## 🚨 Rollback Strategy

```mermaid
stateDiagram-v2
    [*] --> Monitoring: Production deployment
    
    Monitoring --> HealthCheck: Every 30s
    
    state HealthCheck {
        [*] --> CheckNGINX: HTTP health endpoint
        CheckNGINX --> CheckRedis: Redis PING
        CheckRedis --> CheckSSHFS: Mount verification
        CheckSSHFS --> CheckMetrics: Prometheus targets
        CheckMetrics --> [*]: All OK
    }
    
    HealthCheck --> Operational: All healthy
    HealthCheck --> AlertTriggered: Health failure
    
    state AlertTriggered {
        [*] --> EvaluateSeverity: Assess impact
        EvaluateSeverity --> MinorIssue: < 5% error rate
        EvaluateSeverity --> MajorIssue: > 5% error rate
        EvaluateSeverity --> CriticalIssue: > 20% error rate
        
        MinorIssue --> ManualIntervention: Wait for fix
        MajorIssue --> PrepareRollback: Prepare previous version
        CriticalIssue --> ImmediateRollback: Instant rollback
        
        PrepareRollback --> ExecuteRollback: Switch traffic
        ImmediateRollback --> ExecuteRollback
        ExecuteRollback --> VerifyRollback: Health check
        
        VerifyRollback --> RollbackSuccess: Health restored
        VerifyRollback --> RollbackFailed: Still unhealthy
        
        RollbackSuccess --> [*]
        RollbackFailed --> EmergencyProtocol: Manual intervention
        
        ManualIntervention --> [*]: Issue resolved
        EmergencyProtocol --> [*]: Manual fix
    }
    
    Operational --> Monitoring: Continue monitoring
    AlertTriggered --> Monitoring: After resolution
```

## 🔍 Quality Gates

```mermaid
flowchart TD
    subgraph "🚪 Quality Gate Checks"
        START[🚀 Code Commit]
        
        subgraph "Gate 1: Code Quality"
            G1_LINT[📋 Linting Pass<br/>No syntax errors<br/>Style compliance]
            G1_TEST[🧪 Unit Tests<br/>>= 90% coverage<br/>All tests pass]
            G1_SEC[🔒 Security Check<br/>No critical issues<br/>Dependency scan OK]
        end
        
        subgraph "Gate 2: Integration"
            G2_BUILD[🏗️ Build Success<br/>All images build<br/>No layer issues]
            G2_DEPLOY[🐳 Deploy Test<br/>Services start<br/>Health checks pass]
            G2_API[🌐 API Tests<br/>WebP endpoints work<br/>Error handling OK]
        end
        
        subgraph "Gate 3: Performance"
            G3_PERF[⚡ Performance<br/>Response time < 500ms<br/>Memory < 2GB]
            G3_LOAD[📈 Load Test<br/>100 req/s sustained<br/>No memory leaks]
            G3_STRESS[💪 Stress Test<br/>1000 req/s peak<br/>Graceful degradation]
        end
        
        subgraph "Gate 4: Production Ready"
            G4_SECURITY[🛡️ Final Security<br/>Container scan<br/>Config review]
            G4_BACKUP[💾 Backup Test<br/>Data persistence<br/>Recovery procedure]
            G4_MONITOR[📊 Monitoring<br/>Metrics collection<br/>Alert configuration]
        end
    end
    
    subgraph "🎯 Approval Process"
        AUTO_APPROVE[🤖 Auto Approval<br/>All gates pass<br/>Non-production]
        MANUAL_REVIEW[👨‍💼 Manual Review<br/>Production deploy<br/>Architecture changes]
        EMERGENCY[🚨 Emergency Deploy<br/>Hotfix process<br/>Skip non-critical gates]
    end
    
    START --> G1_LINT
    G1_LINT --> G1_TEST
    G1_TEST --> G1_SEC
    
    G1_SEC --> G2_BUILD
    G2_BUILD --> G2_DEPLOY
    G2_DEPLOY --> G2_API
    
    G2_API --> G3_PERF
    G3_PERF --> G3_LOAD
    G3_LOAD --> G3_STRESS
    
    G3_STRESS --> G4_SECURITY
    G4_SECURITY --> G4_BACKUP
    G4_BACKUP --> G4_MONITOR
    
    G4_MONITOR --> AUTO_APPROVE
    G4_MONITOR --> MANUAL_REVIEW
    
    AUTO_APPROVE --> DEPLOY[🚀 Deploy to Environment]
    MANUAL_REVIEW --> DEPLOY
    EMERGENCY --> DEPLOY
    
    %% Failure paths
    G1_LINT -.->|❌| REJECT[❌ Reject Deployment]
    G2_BUILD -.->|❌| REJECT
    G3_PERF -.->|❌| REJECT
    G4_SECURITY -.->|❌| REJECT
    
    REJECT --> START

    style START fill:#4caf50
    style G2_BUILD fill:#2196f3
    style G4_MONITOR fill:#ff9800
    style DEPLOY fill:#8bc34a
    style REJECT fill:#f44336
```