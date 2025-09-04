#!/bin/bash
# Скрипт проверки состояния CDN сервера
# /usr/local/bin/check-cdn-health.sh
# Author: Chibilyaev Alexandr <info@aachibilyaev.com>
# Company: AAChibilyaev LTD

# Конфигурация
MOUNT_POINT="/mnt/bitrix"
CACHE_DIR="/var/cache/webp"
ALERT_EMAIL="info@aachibilyaev.com"
LOG_FILE="/var/log/cdn/health.log"
NGINX_STATUS_URL="http://127.0.0.1/nginx_status"

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Статусы
STATUS_OK=0
STATUS_WARNING=0
STATUS_CRITICAL=0

# Функция логирования
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
    echo -e "$1"
}

# Отправка алерта
send_alert() {
    local subject="$1"
    local message="$2"
    
    # Логируем
    log_message "ALERT: $subject - $message"
    
    # Отправляем email если настроен
    if [ -n "$ALERT_EMAIL" ]; then
        echo "$message" | mail -s "[CDN Alert] $subject" "$ALERT_EMAIL"
    fi
}

# Проверка SSHFS mount
check_mount() {
    echo -e "${YELLOW}Checking SSHFS mount...${NC}"
    
    if mountpoint -q "$MOUNT_POINT"; then
        # Mount существует, проверяем работоспособность
        if timeout 5 ls "$MOUNT_POINT" > /dev/null 2>&1; then
            echo -e "${GREEN}✓ Mount is active and working${NC}"
            return 0
        else
            echo -e "${RED}✗ Mount exists but not responding${NC}"
            STATUS_CRITICAL=1
            send_alert "Mount not responding" "SSHFS mount at $MOUNT_POINT is not responding"
            
            # Пытаемся перемонтировать
            echo "Attempting to remount..."
            if command -v systemctl &> /dev/null; then
                systemctl restart sshfs-mount
            elif command -v docker &> /dev/null; then
                docker restart cdn-sshfs
            else
                echo -e "${RED}✗ Cannot restart mount service${NC}"
                return 1
            fi
            sleep 5
            
            if timeout 5 ls "$MOUNT_POINT" > /dev/null 2>&1; then
                echo -e "${GREEN}✓ Remount successful${NC}"
                return 0
            else
                echo -e "${RED}✗ Remount failed${NC}"
                return 1
            fi
        fi
    else
        echo -e "${RED}✗ Mount point not mounted${NC}"
        STATUS_CRITICAL=1
        send_alert "Mount missing" "SSHFS mount point $MOUNT_POINT is not mounted"
        
        # Пытаемся примонтировать
        echo "Attempting to mount..."
        systemctl start sshfs-mount
        sleep 5
        
        if mountpoint -q "$MOUNT_POINT"; then
            echo -e "${GREEN}✓ Mount successful${NC}"
            return 0
        else
            echo -e "${RED}✗ Mount failed${NC}"
            return 1
        fi
    fi
}

# Проверка NGINX
check_nginx() {
    echo -e "${YELLOW}Checking NGINX...${NC}"
    
    if systemctl is-active --quiet nginx; then
        echo -e "${GREEN}✓ NGINX is running${NC}"
        
        # Проверяем, отвечает ли NGINX
        if curl -s -o /dev/null -w "%{http_code}" "http://localhost" | grep -q "200\|301\|302"; then
            echo -e "${GREEN}✓ NGINX is responding${NC}"
            return 0
        else
            echo -e "${RED}✗ NGINX not responding properly${NC}"
            STATUS_WARNING=1
            return 1
        fi
    else
        echo -e "${RED}✗ NGINX is not running${NC}"
        STATUS_CRITICAL=1
        send_alert "NGINX down" "NGINX service is not running"
        
        # Пытаемся запустить
        echo "Attempting to start NGINX..."
        systemctl start nginx
        sleep 2
        
        if systemctl is-active --quiet nginx; then
            echo -e "${GREEN}✓ NGINX started${NC}"
            return 0
        else
            echo -e "${RED}✗ Failed to start NGINX${NC}"
            return 1
        fi
    fi
}

# Проверка дискового пространства
check_disk_space() {
    echo -e "${YELLOW}Checking disk space...${NC}"
    
    # Проверка основного диска
    local usage=$(df / | awk 'NR==2 {print $5}' | sed 's/%//')
    
    if [ "$usage" -lt 80 ]; then
        echo -e "${GREEN}✓ Disk usage: ${usage}%${NC}"
    elif [ "$usage" -lt 90 ]; then
        echo -e "${YELLOW}⚠ Disk usage: ${usage}% (warning)${NC}"
        STATUS_WARNING=1
    else
        echo -e "${RED}✗ Disk usage: ${usage}% (critical)${NC}"
        STATUS_CRITICAL=1
        send_alert "Disk space critical" "Disk usage is at ${usage}%"
    fi
    
    # Проверка размера кеша
    if [ -d "$CACHE_DIR" ]; then
        local cache_size=$(du -sh "$CACHE_DIR" 2>/dev/null | cut -f1)
        echo -e "  Cache size: $cache_size"
        
        # Если кеш больше 10GB - предупреждение
        local cache_size_mb=$(du -sm "$CACHE_DIR" 2>/dev/null | cut -f1)
        if [ "$cache_size_mb" -gt 10240 ]; then
            echo -e "${YELLOW}⚠ Cache is large (${cache_size}), consider cleanup${NC}"
            STATUS_WARNING=1
        fi
    fi
}

# Проверка процесса конвертации
check_conversion() {
    echo -e "${YELLOW}Checking WebP conversion...${NC}"
    
    # Находим тестовое изображение
    local test_image=$(find "$MOUNT_POINT" -type f -name "*.jpg" -o -name "*.png" | head -1)
    
    if [ -z "$test_image" ]; then
        echo -e "${YELLOW}⚠ No test images found${NC}"
        return 0
    fi
    
    # Пытаемся конвертировать
    local test_output="/tmp/test_conversion.webp"
    if timeout 10 cwebp -q 80 "$test_image" -o "$test_output" 2>/dev/null; then
        if [ -f "$test_output" ] && [ -s "$test_output" ]; then
            echo -e "${GREEN}✓ WebP conversion working${NC}"
            rm -f "$test_output"
            return 0
        else
            echo -e "${RED}✗ WebP conversion failed (empty output)${NC}"
            STATUS_WARNING=1
            return 1
        fi
    else
        echo -e "${RED}✗ WebP conversion failed or timed out${NC}"
        STATUS_WARNING=1
        return 1
    fi
}

# Проверка сетевой связности
check_network() {
    echo -e "${YELLOW}Checking network connectivity...${NC}"
    
    # Пинг до сервера Битрикс (берём из переменной окружения или конфига)
    local bitrix_host="${BITRIX_SERVER_IP:-192.168.1.10}"
    
    if ping -c 1 -W 2 "$bitrix_host" > /dev/null 2>&1; then
        echo -e "${GREEN}✓ Network to Bitrix server OK${NC}"
        
        # Проверка SSH порта
        if nc -z -w2 "$bitrix_host" 22 2>/dev/null; then
            echo -e "${GREEN}✓ SSH port accessible${NC}"
            return 0
        else
            echo -e "${RED}✗ SSH port not accessible${NC}"
            STATUS_CRITICAL=1
            return 1
        fi
    else
        echo -e "${RED}✗ Cannot reach Bitrix server${NC}"
        STATUS_CRITICAL=1
        send_alert "Network issue" "Cannot reach Bitrix server at $bitrix_host"
        return 1
    fi
}

# Проверка производительности
check_performance() {
    echo -e "${YELLOW}Checking performance metrics...${NC}"
    
    # Load average
    local load=$(uptime | awk -F'load average:' '{print $2}')
    echo -e "  Load average:$load"
    
    # Проверка load average (первое значение)
    local load1=$(echo "$load" | cut -d, -f1 | xargs)
    local cpu_count=$(nproc)
    
    # ИСПРАВЛЕНО: Используем awk вместо bc
    if awk "BEGIN {exit !($load1 < $cpu_count)}"; then
        echo -e "${GREEN}✓ Load is normal${NC}"
    else
        echo -e "${YELLOW}⚠ High load detected${NC}"
        STATUS_WARNING=1
    fi
    
    # Memory usage
    local mem_usage=$(free | grep Mem | awk '{print int($3/$2 * 100)}')
    if [ "$mem_usage" -lt 80 ]; then
        echo -e "${GREEN}✓ Memory usage: ${mem_usage}%${NC}"
    elif [ "$mem_usage" -lt 90 ]; then
        echo -e "${YELLOW}⚠ Memory usage: ${mem_usage}% (warning)${NC}"
        STATUS_WARNING=1
    else
        echo -e "${RED}✗ Memory usage: ${mem_usage}% (critical)${NC}"
        STATUS_CRITICAL=1
    fi
}

# Статистика кеша
show_cache_stats() {
    echo -e "${YELLOW}Cache statistics:${NC}"
    
    if [ -d "$CACHE_DIR" ]; then
        local total_files=$(find "$CACHE_DIR" -type f -name "*.webp" 2>/dev/null | wc -l)
        local cache_size=$(du -sh "$CACHE_DIR" 2>/dev/null | cut -f1)
        local newest_file=$(find "$CACHE_DIR" -type f -name "*.webp" -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -1 | cut -d' ' -f2-)
        
        echo "  Total WebP files: $total_files"
        echo "  Cache size: $cache_size"
        
        if [ -n "$newest_file" ]; then
            echo "  Latest conversion: $(stat -c %y "$newest_file" | cut -d. -f1)"
        fi
    else
        echo "  Cache directory not found"
    fi
}

# Основная функция
main() {
    echo "========================================="
    echo "CDN Server Health Check"
    echo "Time: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "========================================="
    
    # Создаем лог директорию если нет
    mkdir -p "$(dirname "$LOG_FILE")"
    
    # Выполняем проверки
    check_mount
    echo ""
    
    check_nginx
    echo ""
    
    check_disk_space
    echo ""
    
    check_conversion
    echo ""
    
    check_network
    echo ""
    
    check_performance
    echo ""
    
    show_cache_stats
    echo ""
    
    # Итоговый статус
    echo "========================================="
    if [ "$STATUS_CRITICAL" -eq 1 ]; then
        echo -e "${RED}Overall Status: CRITICAL${NC}"
        exit 2
    elif [ "$STATUS_WARNING" -eq 1 ]; then
        echo -e "${YELLOW}Overall Status: WARNING${NC}"
        exit 1
    else
        echo -e "${GREEN}Overall Status: OK${NC}"
        exit 0
    fi
}

# Запуск
main
