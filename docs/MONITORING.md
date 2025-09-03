# 📊 Мониторинг CDN системы

## 🎯 Обзор системы мониторинга

Полный стек мониторинга включает:
- **Prometheus** - сбор и хранение метрик
- **Grafana** - визуализация и дашборды
- **Alertmanager** - управление алертами
- **Health Checks** - проверки состояния
- **Логирование** - централизованные логи

## 📈 Grafana Dashboards

### CDN Overview Dashboard

![Dashboard Preview](https://via.placeholder.com/800x400?text=CDN+Overview+Dashboard)

**Ключевые виджеты:**

1. **Request Rate** - количество запросов в секунду
2. **Cache Hit Ratio** - процент попаданий в кеш
3. **Response Time** - время ответа (P50, P95, P99)
4. **Active Connections** - активные соединения
5. **Bandwidth Usage** - использование полосы
6. **Error Rate** - процент ошибок

### Доступ к Grafana

```bash
# URL доступа
http://localhost:3000

# Credentials
Username: admin
Password: TErmokit2024CDN!
```

## 🔍 Prometheus метрики

### Основные метрики

```yaml
# Request metrics
nginx_http_requests_total
nginx_http_request_duration_seconds
nginx_http_response_size_bytes

# Cache metrics
cache_hit_ratio
cache_size_bytes
cache_files_total
webp_conversion_duration_seconds
webp_conversion_errors_total

# System metrics
node_cpu_usage_percent
node_memory_usage_bytes
node_disk_usage_bytes
node_network_receive_bytes_total
node_network_transmit_bytes_total
```

### Примеры запросов PromQL

```promql
# Cache Hit Ratio за последний час
rate(cache_hits_total[1h]) / rate(cache_requests_total[1h]) * 100

# Среднее время конвертации WebP
rate(webp_conversion_duration_seconds_sum[5m]) / rate(webp_conversion_duration_seconds_count[5m])

# Top 5 самых запрашиваемых изображений
topk(5, sum by (path) (rate(nginx_http_requests_total[1h])))

# Процент ошибок 5xx
rate(nginx_http_requests_total{status=~"5.."}[5m]) / rate(nginx_http_requests_total[5m]) * 100
```

## 🚨 Алерты и уведомления

### Критические алерты

```yaml
groups:
  - name: critical
    rules:
      - alert: CDNDown
        expr: up{job="nginx"} == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "CDN сервер недоступен"
          description: "NGINX не отвечает более 1 минуты"

      - alert: DiskSpaceCritical
        expr: node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"} < 0.05
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Критически мало места на диске"
          description: "Осталось менее 5% свободного места"

      - alert: SSHFSMountDown
        expr: sshfs_mount_status == 0
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "SSHFS mount недоступен"
          description: "Потеряно соединение с Битрикс сервером"
```

### Warning алерты

```yaml
- alert: HighErrorRate
  expr: rate(nginx_http_requests_total{status=~"5.."}[5m]) > 0.05
  for: 5m
  labels:
    severity: warning
  annotations:
    summary: "Высокий процент ошибок"
    description: "Более 5% запросов возвращают 5xx ошибки"

- alert: CacheSizeLarge
  expr: webp_cache_size_bytes > 10737418240
  for: 30m
  labels:
    severity: warning
  annotations:
    summary: "Большой размер кеша"
    description: "Кеш WebP превысил 10GB"

- alert: SlowResponseTime
  expr: histogram_quantile(0.95, rate(nginx_http_request_duration_seconds_bucket[5m])) > 1
  for: 10m
  labels:
    severity: warning
  annotations:
    summary: "Медленное время ответа"
    description: "P95 время ответа превышает 1 секунду"
```

## 📝 Логирование

### Структура логов

```
/logs/
├── nginx/
│   ├── access.log       # Все запросы
│   ├── error.log        # Ошибки NGINX
│   └── cdn.access.log   # CDN специфичные логи
├── converter/
│   └── converter.log    # Логи конвертации
├── sshfs/
│   └── mount.log       # Логи монтирования
└── health/
    └── health.log      # Health check логи
```

### Формат логов NGINX

```nginx
log_format cdn '$remote_addr - $remote_user [$time_local] "$request" '
               '$status $body_bytes_sent "$http_referer" '
               '"$http_user_agent" "$http_x_forwarded_for" '
               'rt=$request_time uct="$upstream_connect_time" '
               'uht="$upstream_header_time" urt="$upstream_response_time" '
               'cs=$upstream_cache_status';
```

### Анализ логов

```bash
# Top 10 самых запрашиваемых файлов
awk '{print $7}' /logs/nginx/cdn.access.log | sort | uniq -c | sort -rn | head -10

# Запросы с ошибками 5xx
grep " 5[0-9][0-9] " /logs/nginx/cdn.access.log

# Среднее время ответа
awk '{sum+=$NF; count++} END {print sum/count}' /logs/nginx/cdn.access.log

# WebP конвертации за последний час
grep "Converted" /logs/converter/converter.log | grep "$(date -d '1 hour ago' '+%Y-%m-%d %H')"
```

## 🔧 Health Checks

### Автоматические проверки

```bash
# Скрипт health check запускается каждые 30 секунд
*/30 * * * * /monitoring/check-health.sh
```

### Компоненты проверки

1. **SSHFS Mount**
   - Проверка доступности mount point
   - Тест чтения файла
   - Auto-remount при сбое

2. **NGINX**
   - HTTP endpoint проверка
   - Проверка конфигурации
   - Reload при необходимости

3. **WebP Converter**
   - Проверка процесса
   - Тест конвертации
   - Restart при зависании

4. **Redis**
   - Ping проверка
   - Memory usage
   - Persistence проверка

### Health endpoints

```bash
# NGINX health
curl http://localhost/health

# NGINX status
curl http://localhost/nginx_status

# Полная проверка системы
docker exec cdn-healthcheck /app/healthcheck.sh
```

## 📊 Мониторинг в реальном времени

### CLI мониторинг

```bash
# Статус всех сервисов
./docker-manage.sh status

# Реальный мониторинг логов
./docker-manage.sh logs -f

# Статистика кеша
./docker-manage.sh stats

# Top процессы
docker stats --no-stream
```

### Полезные команды

```bash
# Размер кеша WebP
du -sh /var/cache/webp

# Количество файлов в кеше
find /var/cache/webp -type f -name "*.webp" | wc -l

# Активные соединения NGINX
docker exec cdn-nginx netstat -an | grep :80 | wc -l

# Использование памяти Redis
docker exec cdn-redis redis-cli INFO memory | grep used_memory_human

# Queue конвертера
docker exec cdn-webp-converter python -c "import redis; r=redis.Redis('redis'); print(r.llen('conversion_queue'))"
```

## 🎯 KPI и SLA

### Целевые показатели

| Метрика | Цель | Критический порог |
|---------|------|-------------------|
| **Uptime** | 99.9% | < 99.5% |
| **Cache Hit Ratio** | > 90% | < 80% |
| **Response Time P95** | < 100ms | > 500ms |
| **Error Rate** | < 0.1% | > 1% |
| **Conversion Success** | > 99% | < 95% |

### Расчет SLA

```python
# Uptime за месяц
uptime_percent = (total_minutes - downtime_minutes) / total_minutes * 100

# Допустимый downtime при 99.9% SLA
# Месяц: 43.2 минуты
# Неделя: 10.1 минуты
# День: 1.44 минуты
```

## 🔄 Автоматизация

### Auto-recovery сценарии

```bash
#!/bin/bash
# auto-recovery.sh

# Проверка и восстановление SSHFS
if ! mountpoint -q /mnt/bitrix; then
    docker restart cdn-sshfs
    sleep 10
    if ! mountpoint -q /mnt/bitrix; then
        # Отправка алерта
        curl -X POST $SLACK_WEBHOOK -d '{"text":"CRITICAL: SSHFS mount failed"}'
    fi
fi

# Проверка и перезапуск зависших сервисов
for service in nginx webp-converter redis; do
    if ! docker ps | grep -q "cdn-$service"; then
        docker-compose up -d $service
        echo "Restarted $service at $(date)" >> /logs/recovery.log
    fi
done
```

### Backup метрик

```bash
# Ежедневный backup Prometheus данных
0 3 * * * docker exec cdn-prometheus tar czf /backup/prometheus-$(date +%Y%m%d).tar.gz /prometheus

# Экспорт Grafana dashboards
0 4 * * * docker exec cdn-grafana grafana-cli admin export-dashboard > /backup/dashboards-$(date +%Y%m%d).json
```

## 📱 Интеграции

### Telegram уведомления

```python
# telegram_alert.py
import requests

def send_alert(message, chat_id, bot_token):
    url = f"https://api.telegram.org/bot{bot_token}/sendMessage"
    data = {
        "chat_id": chat_id,
        "text": f"🚨 CDN Alert:\n{message}",
        "parse_mode": "HTML"
    }
    requests.post(url, data=data)
```

### Webhook для Slack

```yaml
# alertmanager.yml
receivers:
  - name: 'slack'
    slack_configs:
      - api_url: 'YOUR_SLACK_WEBHOOK_URL'
        channel: '#cdn-alerts'
        title: 'CDN Alert'
        text: '{{ .GroupLabels.alertname }}'
```