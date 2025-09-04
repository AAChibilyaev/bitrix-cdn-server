# 🌐 Сетевые потоки и взаимодействие контейнеров

**Автор**: Chibilyaev Alexandr | **AAChibilyaev LTD** | info@aachibilyaev.com

## 🔀 Схема сетевого взаимодействия

```mermaid
graph TB
    subgraph "🌍 Internet"
        USER[👤 Browser<br/>Accept: image/webp]
        BOT[🤖 Search Bots<br/>Crawlers]
    end
    
    subgraph "🔀 Load Balancer (Optional)"
        LB[⚖️ CloudFlare/AWS LB<br/>DDoS Protection]
    end
    
    subgraph "🐳 CDN Server - Docker Network"
        subgraph "Frontend Layer"
            NGINX[🌐 NGINX<br/>:80 :443<br/>Rate Limiting<br/>SSL Termination]
            VARNISH[⚡ Varnish<br/>:8080<br/>RAM Cache<br/>ESI Processing]
        end
        
        subgraph "Application Layer"  
            CONVERTER[🎨 WebP Converter<br/>Python Service<br/>File Watcher<br/>cwebp Engine]
        end
        
        subgraph "Storage Layer"
            REDIS[🔴 Redis<br/>:6379<br/>Metadata Cache<br/>Session Storage]
            SSHFS[📂 SSHFS Mount<br/>Remote File Access<br/>Keep-Alive SSH]
        end
        
        subgraph "Monitoring Layer"
            PROMETHEUS[📊 Prometheus<br/>:9090<br/>Metrics Collection]
            GRAFANA[📈 Grafana<br/>:3000<br/>Visualization]
            EXPORTERS[📊 Exporters<br/>:9100,:9113,:9121<br/>System/NGINX/Redis]
        end
        
        subgraph "Security Layer"
            CERTBOT[🔐 Certbot<br/>SSL Automation<br/>Let's Encrypt]
        end
    end
    
    subgraph "🖥️ Bitrix Server"
        BITRIX[🌐 Bitrix CMS<br/>:22 SSH<br/>/var/www/upload/]
        FILES[📁 Original Files<br/>Images Storage]
    end
    
    %% External traffic flow
    USER --> LB
    BOT --> LB
    LB --> NGINX
    
    %% Request handling flow
    NGINX -->|Cache Check| VARNISH
    VARNISH -->|HIT| USER
    VARNISH -->|MISS| NGINX
    NGINX -->|WebP Request| CONVERTER
    NGINX -->|Original Request| SSHFS
    
    %% Backend communication
    CONVERTER --> REDIS
    CONVERTER --> SSHFS
    SSHFS -->|SSH:22| BITRIX
    BITRIX --> FILES
    
    %% Monitoring flows
    EXPORTERS --> NGINX
    EXPORTERS --> REDIS
    EXPORTERS --> HOST[Host System]
    PROMETHEUS --> EXPORTERS
    GRAFANA --> PROMETHEUS
    
    %% SSL automation
    CERTBOT -->|HTTP-01 Challenge| NGINX
    NGINX --> CERTBOT
    
    %% Health checks
    PROMETHEUS -->|Health Probes| NGINX
    PROMETHEUS -->|Health Probes| REDIS
    PROMETHEUS -->|Health Probes| SSHFS

    style USER fill:#e3f2fd
    style NGINX fill:#4caf50
    style CONVERTER fill:#2196f3
    style REDIS fill:#f44336
    style BITRIX fill:#ff9800
    style PROMETHEUS fill:#9c27b0
```

## 🔌 Port Mapping & Service Discovery

```mermaid
graph LR
    subgraph "🌐 External Ports"
        P80[":80<br/>HTTP"]
        P443[":443<br/>HTTPS"]
        P3000[":3000<br/>Grafana"]
        P9090[":9090<br/>Prometheus"]
    end
    
    subgraph "🐳 Container Ports"
        subgraph "Primary Services"
            N80[nginx:80]
            N443[nginx:443]
        end
        
        subgraph "Cache Services"
            V80[varnish:80]
            R6379[redis:6379]
        end
        
        subgraph "Monitoring Services"
            P9090_INT[prometheus:9090]
            G3000[grafana:3000]
            NE9113[nginx-exporter:9113]
            RE9121[redis-exporter:9121]
            NODE9100[node-exporter:9100]
        end
        
        subgraph "Internal Services"
            WC[webp-converter<br/>No exposed ports]
            SF[sshfs<br/>No exposed ports]
            CB[certbot<br/>No exposed ports]
        end
    end
    
    subgraph "🔒 Security Rules"
        LOCALHOST["127.0.0.1 only<br/>Monitoring ports"]
        PUBLIC["0.0.0.0<br/>Web ports"]
    end
    
    %% Port mappings
    P80 --> N80
    P443 --> N443
    P3000 --> G3000
    P9090 --> P9090_INT
    
    %% Internal communication
    N80 -.->|Backend| V80
    N80 -.->|Metrics| NE9113
    R6379 -.->|Metrics| RE9121
    
    %% Security bindings
    LOCALHOST --> P3000
    LOCALHOST --> P9090
    PUBLIC --> P80
    PUBLIC --> P443
    
    style P80 fill:#4caf50
    style P443 fill:#8bc34a
    style P3000 fill:#9c27b0
    style P9090 fill:#ff9800
    style LOCALHOST fill:#ffeb3b
    style PUBLIC fill:#f44336
```

## 📊 Data Flow Between Containers

```mermaid
flowchart TD
    subgraph "📡 Request Processing"
        REQ[🌐 HTTP Request<br/>GET /upload/image.jpg]
        
        REQ --> NGINX_CHECK{🔍 NGINX<br/>Accept: image/webp?}
        
        NGINX_CHECK -->|Yes| WEBP_CHECK{📁 WebP Cache<br/>Exists?}
        NGINX_CHECK -->|No| ORIG_CHECK{📁 Original<br/>Exists?}
        
        WEBP_CHECK -->|Hit| CACHE_SERVE[⚡ Serve from Cache<br/>200 OK + WebP]
        WEBP_CHECK -->|Miss| CONVERT[🔄 Convert via<br/>webp-converter]
        
        ORIG_CHECK -->|Hit| ORIG_SERVE[📄 Serve Original<br/>200 OK + JPEG/PNG]
        ORIG_CHECK -->|Miss| NOT_FOUND[❌ 404 Not Found]
        
        CONVERT --> SSHFS_READ[📂 SSHFS Read<br/>from Bitrix Server]
        SSHFS_READ --> WEBP_GEN[🎨 cwebp Generation<br/>Quality: 85]
        WEBP_GEN --> CACHE_SAVE[💾 Save to Cache<br/>+ Redis Metadata]
        CACHE_SAVE --> WEBP_SERVE[⚡ Serve WebP<br/>200 OK]
    end
    
    subgraph "📊 Monitoring Flow"
        METRICS[📈 Metrics Collection]
        
        NGINX_CHECK -.->|Request Count| METRICS
        CACHE_SERVE -.->|Cache Hit| METRICS  
        CONVERT -.->|Conversion Time| METRICS
        SSHFS_READ -.->|SSHFS Latency| METRICS
        
        METRICS --> PROMETHEUS_STORE[📊 Prometheus<br/>Time Series DB]
        PROMETHEUS_STORE --> GRAFANA_VIZ[📈 Grafana<br/>Visualization]
        
        GRAFANA_VIZ --> ALERTS{🚨 Alert Rules<br/>Triggered?}
        ALERTS -->|Yes| NOTIFICATION[📧 Send Alert<br/>Email/Slack/Telegram]
        ALERTS -->|No| MONITOR[👀 Continue Monitoring]
    end
    
    subgraph "🔄 Background Processes"
        CLEANUP[🧹 Cache Cleanup<br/>Every 24h]
        RENEWAL[🔒 SSL Renewal<br/>Every 12h]
        BACKUP[💾 Config Backup<br/>Daily]
        HEALTHCHECK[❤️ Health Checks<br/>Every 30s]
        
        CLEANUP --> CACHE_SAVE
        RENEWAL --> NGINX_CHECK
        HEALTHCHECK --> CONVERT
        HEALTHCHECK --> SSHFS_READ
    end

    style REQ fill:#e3f2fd
    style NGINX_CHECK fill:#4caf50
    style CONVERT fill:#2196f3
    style CACHE_SERVE fill:#8bc34a
    style METRICS fill:#ff9800
    style CLEANUP fill:#9c27b0
```

## 🔗 Inter-Container Communication

```mermaid
graph TB
    subgraph "🔀 Communication Matrix"
        subgraph "Primary Services"
            NGINX[🌐 nginx<br/>Entry Point]
            CONVERTER[🎨 webp-converter<br/>Image Processing]
            SSHFS[📂 sshfs<br/>File Mount]
        end
        
        subgraph "Support Services"
            REDIS[🔴 redis<br/>Metadata]
            VARNISH[⚡ varnish<br/>HTTP Cache]
            CERTBOT[🔒 certbot<br/>SSL Automation]
        end
        
        subgraph "Monitoring Services"
            PROMETHEUS[📊 prometheus<br/>Metrics Hub]
            GRAFANA[📈 grafana<br/>Dashboards]
            NGINX_EXP[📊 nginx-exporter]
            REDIS_EXP[📊 redis-exporter]
            NODE_EXP[📊 node-exporter]
        end
    end
    
    %% Primary communication flows
    NGINX -.->|"HTTP/TCP"| CONVERTER
    NGINX -.->|"File Access"| SSHFS
    CONVERTER -.->|"File Read"| SSHFS
    CONVERTER -.->|"Cache Metadata"| REDIS
    NGINX -.->|"Optional"| VARNISH
    
    %% Monitoring flows
    PROMETHEUS -.->|"HTTP Scrape"| NGINX_EXP
    PROMETHEUS -.->|"HTTP Scrape"| REDIS_EXP
    PROMETHEUS -.->|"HTTP Scrape"| NODE_EXP
    NGINX_EXP -.->|"Status Page"| NGINX
    REDIS_EXP -.->|"Redis Protocol"| REDIS
    GRAFANA -.->|"PromQL"| PROMETHEUS
    
    %% SSL automation
    CERTBOT -.->|"HTTP Challenge"| NGINX
    
    %% External connections
    SSHFS -.->|"SSH:22"| BITRIX_EXT[🖥️ Bitrix Server<br/>External]
    NGINX -.->|"HTTPS:443"| USERS_EXT[👥 Users<br/>External]
    
    style NGINX fill:#4caf50
    style CONVERTER fill:#2196f3
    style SSHFS fill:#ff9800
    style REDIS fill:#f44336
    style PROMETHEUS fill:#9c27b0
    style BITRIX_EXT fill:#ffeb3b
    style USERS_EXT fill:#e1f5fe
```