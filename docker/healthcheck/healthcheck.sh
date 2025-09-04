#!/bin/bash
# Docker CDN Health Check Script

# Конфигурация
NGINX_URL="http://nginx/health"
NGINX_STATUS_URL="http://nginx/nginx_status"
REDIS_HOST="redis"
REDIS_PORT="6379"
ALERT_EMAIL="${ALERT_EMAIL:-admin@termokit.ru}"
LOG_FILE="/var/log/cdn/health.log"

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Статусы
STATUS_OK=0
STATUS_WARNING=0
STATUS_CRITICAL=0

# Функция логирования
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Проверка NGINX
check_nginx() {
    log_message "Checking NGINX health..."
    
    if curl -sf -o /dev/null -w "%{http_code}" "$NGINX_URL" | grep -q "200"; then
        log_message "✓ NGINX is healthy"
        
        # Проверяем статистику NGINX
        if STATS=$(curl -sf "$NGINX_STATUS_URL" 2>/dev/null); then
            ACTIVE=$(echo "$STATS" | grep "Active" | awk '{print $3}')
            log_message "  Active connections: $ACTIVE"
        fi
        return 0
    else
        log_message "✗ NGINX is not responding"
        STATUS_CRITICAL=1
        return 1
    fi
}

# Проверка Redis
check_redis() {
    log_message "Checking Redis..."
    
    if nc -z -w2 "$REDIS_HOST" "$REDIS_PORT" 2>/dev/null; then
        log_message "✓ Redis is accessible"
        return 0
    else
        log_message "⚠ Redis is not accessible (non-critical)"
        STATUS_WARNING=1
        return 1
    fi
}

# Проверка WebP конвертера
check_converter() {
    log_message "Checking WebP converter..."
    
    # ИСПРАВЛЕНО: Проверяем правильное имя контейнера
    if docker ps --format "table {{.Names}}\t{{.Status}}" | grep -q "cdn-webp-converter.*Up"; then
        log_message "✓ WebP converter is running"
        
        # Проверяем логи на ошибки
        ERROR_COUNT=$(docker logs cdn-webp-converter --tail 100 2>&1 | grep -c "ERROR" || true)
        if [ "$ERROR_COUNT" -gt 0 ]; then
            log_message "⚠ Found $ERROR_COUNT errors in converter logs"
            STATUS_WARNING=1
        fi
        return 0
    else
        log_message "✗ WebP converter is not running"
        STATUS_CRITICAL=1
        return 1
    fi
}

# Проверка SSHFS монтирования
check_mount() {
    log_message "Checking SSHFS mount..."
    
    # Проверяем контейнер SSHFS
    if docker ps --format "table {{.Names}}\t{{.Status}}" | grep -q "cdn-sshfs.*Up"; then
        # Проверяем health status контейнера
        HEALTH=$(docker inspect cdn-sshfs | jq -r '.[0].State.Health.Status' 2>/dev/null)
        
        if [ "$HEALTH" = "healthy" ]; then
            log_message "✓ SSHFS mount is healthy"
            return 0
        else
            log_message "✗ SSHFS mount is unhealthy (status: $HEALTH)"
            STATUS_CRITICAL=1
            return 1
        fi
    else
        log_message "✗ SSHFS container is not running"
        STATUS_CRITICAL=1
        return 1
    fi
}

# Проверка Varnish (если включен)
check_varnish() {
    if docker ps --format "{{.Names}}" | grep -q "cdn-varnish"; then
        log_message "Checking Varnish cache..."
        
        if curl -sf -o /dev/null "http://varnish:80/health"; then
            log_message "✓ Varnish is healthy"
            return 0
        else
            log_message "⚠ Varnish is not responding"
            STATUS_WARNING=1
            return 1
        fi
    fi
    return 0
}

# Проверка дискового пространства
check_disk_space() {
    log_message "Checking disk space..."
    
    # Проверяем основной диск
    USAGE=$(df / | awk 'NR==2 {print int($5)}')
    
    if [ "$USAGE" -lt 80 ]; then
        log_message "✓ Disk usage: ${USAGE}%"
    elif [ "$USAGE" -lt 90 ]; then
        log_message "⚠ Disk usage: ${USAGE}% (warning)"
        STATUS_WARNING=1
    else
        log_message "✗ Disk usage: ${USAGE}% (critical)"
        STATUS_CRITICAL=1
    fi
}

# Статистика кеша
show_cache_stats() {
    log_message "Cache statistics:"
    
    # Получаем статистику из Redis если доступен
    if nc -z -w2 "$REDIS_HOST" "$REDIS_PORT" 2>/dev/null; then
        # Здесь можно добавить получение статистики из Redis
        log_message "  Redis cache available"
    fi
    
    # Проверяем размер WebP кеша через Docker volume
    if docker volume inspect cdn_webp-cache &>/dev/null; then
        CACHE_SIZE=$(docker run --rm -v cdn_webp-cache:/cache alpine du -sh /cache 2>/dev/null | cut -f1)
        log_message "  WebP cache size: ${CACHE_SIZE:-unknown}"
    fi
}

# Отправка алерта
send_alert() {
    local subject="$1"
    local message="$2"
    
    log_message "ALERT: $subject - $message"
    
    # Здесь можно добавить отправку email или webhook
    # echo "$message" | mail -s "[CDN Alert] $subject" "$ALERT_EMAIL"
}

# Основная функция
main() {
    log_message "========================================="
    log_message "CDN Docker Health Check"
    log_message "========================================="
    
    # Выполняем проверки
    check_nginx
    check_redis
    check_converter
    check_mount
    check_varnish
    check_disk_space
    show_cache_stats
    
    # Итоговый статус
    log_message "========================================="
    if [ "$STATUS_CRITICAL" -eq 1 ]; then
        log_message "Overall Status: CRITICAL"
        send_alert "CDN Critical" "Critical issues detected in CDN services"
        exit 2
    elif [ "$STATUS_WARNING" -eq 1 ]; then
        log_message "Overall Status: WARNING"
        exit 1
    else
        log_message "Overall Status: OK"
        exit 0
    fi
}

# Запуск
main