# 🏗️ Архитектура Битрикс CDN Server

**Автор**: Chibilyaev Alexandr | **AAChibilyaev LTD** | info@aachibilyaev.com

## ⚠️ КРИТИЧЕСКИ ВАЖНО: Два физически разных сервера!

### 📍 Сервер 1 - Битрикс (основной)
- **Расположение**: Ваш production сервер
- **Файлы**: `/var/www/bitrix/upload/` - ВСЕ оригиналы тут
- **Роль**: Хранение, загрузка, управление файлами
- **WebP**: НЕ создает, НЕ хранит

### 📍 Сервер 2 - CDN (этот проект)  
- **Расположение**: Отдельный сервер/VPS
- **Оригиналы**: `/mnt/bitrix/upload/` - READ-ONLY mount с Сервера 1
- **WebP кеш**: `/var/cache/webp/` - ЛОКАЛЬНЫЕ WebP версии
- **Роль**: Конвертация и отдача оптимизированных изображений

## 📊 Полная схема архитектуры

```mermaid
graph TB
    subgraph "🖥️ СЕРВЕР 1 - БИТРИКС"
        B["/var/www/bitrix/upload/<br/>Оригинальные файлы"]
        PHP[PHP/MySQL/Apache]
    end
    
    subgraph "⚡ CDN Server"
        subgraph "🐳 Docker Network 172.25.0.0/24"
            subgraph "Frontend Layer"
                NG[NGINX<br/>:80/:443<br/>cdn-nginx]
                VN[Varnish Cache<br/>:8080<br/>cdn-varnish]
            end
            
            subgraph "Processing Layer"
                WC[WebP Converter<br/>Python Service<br/>cdn-webp-converter]
                SF[SSHFS Mount<br/>cdn-sshfs]
            end
            
            subgraph "Storage Layer"
                RD[Redis<br/>:6379<br/>cdn-redis]
                CACHE[(WebP Cache<br/>/var/cache/webp)]
                MOUNT[(Mounted Files<br/>/mnt/bitrix)]
            end
            
            subgraph "Monitoring Layer"
                PR[Prometheus<br/>:9090<br/>cdn-prometheus]
                GR[Grafana<br/>:3000<br/>cdn-grafana]
                NE[NGINX Exporter<br/>:9113<br/>cdn-nginx-exporter]
                RE[Redis Exporter<br/>:9121<br/>cdn-redis-exporter]
                NODE[Node Exporter<br/>:9100<br/>cdn-node-exporter]
            end
            
            subgraph "SSL Layer"
                CB[Certbot<br/>cdn-certbot]
                SSL[(SSL Certs<br/>/etc/letsencrypt)]
            end
        end
    end
    
    U[👤 Пользователь] -->|HTTPS/443| NG
    NG --> VN
    VN --> CACHE
    NG -->|map $webp_suffix| WC
    WC --> MOUNT
    SF -->|SSH/22| B
    WC --> RD
    CB --> SSL
    NG --> SSL
    
    PR --> NG
    PR --> WC
    PR --> RD
    PR --> RE
    PR --> NODE
    NE --> NG
    RE --> RD
    NODE --> NG
    GR --> PR
```

## 🔄 Компоненты и их взаимодействие

### 1. Frontend Layer

#### NGINX (порты 80, 443)
- **Роль**: Главный веб-сервер и точка входа
- **Функции**:
  - Прием HTTP/HTTPS запросов
  - Проверка поддержки WebP в браузере
  - Маршрутизация к кешу или конвертеру
  - SSL терминация
  - Rate limiting и защита от DDoS

```nginx
# Основная логика обработки (без if в location - nginx.org best practice)
map $http_accept $webp_suffix {
    default "";
    "~*image/webp" ".webp";
}

location ~* \.(jpg|jpeg|png|gif|bmp)$ {
    # Пробуем WebP версию, затем оригинал
    try_files /var/cache/webp$uri$webp_suffix $uri @webp_convert;
}

location @webp_convert {
    # Проксирование на WebP конвертер
    proxy_pass http://webp-converter:8080;
    proxy_set_header X-Original-URI $request_uri;
}
```

#### Varnish Cache (порт 8080)
- **Роль**: HTTP акселератор
- **Функции**:
  - Кеширование в RAM
  - Снижение нагрузки на NGINX
  - Grace mode для отдачи устаревшего кеша

### 2. Processing Layer

#### WebP Converter
- **Язык**: Python 3 + cwebp
- **Функции**:
  - On-the-fly конвертация изображений
  - Оптимизация размера и качества
  - Batch обработка при старте
  - File watcher для новых файлов

```python
# Основные параметры конвертации
QUALITY = 85
MAX_WIDTH = 2048
MAX_HEIGHT = 2048
COMPRESSION_LEVEL = 6
```

#### SSHFS Mount
- **Роль**: Безопасное монтирование файлов
- **Параметры**:
  - Read-only монтирование
  - Auto-reconnect при обрыве
  - Кеширование метаданных

### 3. Storage Layer

#### Redis
- **Роль**: Кеш метаданных
- **Хранит**:
  - Информацию о конвертированных файлах
  - Статистику использования
  - Временные данные обработки

#### Cache Storage
```
/var/cache/webp/
├── upload/
│   ├── iblock/
│   │   ├── 001/
│   │   │   ├── image1.jpg.webp
│   │   │   └── image2.png.webp
│   │   └── 002/
│   └── resize_cache/
└── .metadata/
    └── cache.db
```

### 4. Monitoring Layer

#### Prometheus
- **Метрики**:
  - Request rate
  - Response time (P50, P95, P99)
  - Cache hit ratio
  - Conversion rate
  - Error rate

#### Grafana Dashboards
- CDN Overview
- Performance Metrics
- Cache Statistics
- Error Analysis
- Real-time Monitoring

## 🔐 Сетевая безопасность

### Docker Network Isolation
```yaml
networks:
  cdn-network:
    driver: bridge
    ipam:
      config:
        - subnet: 172.25.0.0/24
```

### Firewall правила
```bash
# Только необходимые порты
-A INPUT -p tcp --dport 80 -j ACCEPT
-A INPUT -p tcp --dport 443 -j ACCEPT
-A INPUT -p tcp --dport 3000 -s 192.168.1.0/24 -j ACCEPT  # Grafana только из локальной сети
```

## 📦 Volumes и персистентность

| Volume | Тип | Описание | Backup |
|--------|-----|----------|--------|
| `bitrix-files` | local | SSHFS mount point | ❌ |
| `webp-cache` | local | Конвертированные изображения | ✅ |
| `redis-data` | local | Redis персистентность | ✅ |
| `prometheus-data` | local | Метрики | ✅ |
| `grafana-data` | local | Дашборды и настройки | ✅ |
| `ssl-certs` | local | SSL сертификаты | ✅ |

## 🔄 Процессы и потоки

### Основной поток обработки
1. **Прием запроса** → NGINX
2. **Проверка кеша** → Varnish/Disk
3. **При промахе** → WebP Converter
4. **Чтение оригинала** → SSHFS Mount
5. **Конвертация** → cwebp
6. **Сохранение** → Cache + Redis
7. **Отдача клиенту** → NGINX

### Background процессы
- **Health checks** - каждые 30 секунд
- **Cache cleanup** - каждые 24 часа
- **Metrics collection** - каждые 15 секунд
- **Log rotation** - каждые 7 дней
- **SSL renewal** - каждые 12 часов проверка

## 🚀 Масштабирование

### Горизонтальное масштабирование
```yaml
# docker-compose.scale.yml
services:
  webp-converter:
    deploy:
      replicas: 3
  
  nginx:
    deploy:
      replicas: 2
```

### Вертикальное масштабирование
```yaml
services:
  webp-converter:
    deploy:
      resources:
        limits:
          cpus: '4'
          memory: 4G
```

## 📊 Ресурсные лимиты

| Сервис | CPU | RAM | Disk I/O |
|--------|-----|-----|----------|
| NGINX | 2 cores | 1GB | unlimited |
| WebP Converter | 2 cores | 2GB | 100MB/s |
| Redis | 1 core | 512MB | 50MB/s |
| Varnish | 2 cores | 1GB | unlimited |
| SSHFS | 0.5 cores | 256MB | network limited |

## 🔧 Конфигурационные файлы

```
bitrix-cdn/
├── docker-compose.yml           # Основная конфигурация
├── docker-compose.prod.yml      # Production overrides
├── docker-compose.scale.yml     # Scaling configuration
├── .env                         # Environment variables
├── docker/
│   ├── nginx/nginx.conf        # NGINX конфигурация
│   ├── nginx/conf.d/*.conf     # Сайты NGINX
│   ├── varnish/default.vcl     # Varnish конфигурация
│   ├── prometheus/prometheus.yml
│   └── grafana/provisioning/
└── configs/
    └── optimization.json        # Параметры оптимизации
```