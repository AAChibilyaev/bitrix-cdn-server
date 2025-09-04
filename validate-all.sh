#!/bin/bash
# Скрипт валидации всех конфигураций Bitrix CDN Server
# Проверяет синтаксис всех конфигурационных файлов по официальной документации
# Author: Chibilyaev Alexandr <info@aachibilyaev.com>
# Company: AAChibilyaev LTD

set -e

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Счетчики
TOTAL_CHECKS=0
PASSED_CHECKS=0
FAILED_CHECKS=0

# Функция вывода результата
check_result() {
    local status=$1
    local message=$2
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    
    if [ $status -eq 0 ]; then
        echo -e "${GREEN}✅ PASS${NC}: $message"
        PASSED_CHECKS=$((PASSED_CHECKS + 1))
    else
        echo -e "${RED}❌ FAIL${NC}: $message"
        FAILED_CHECKS=$((FAILED_CHECKS + 1))
    fi
}

echo "=========================================="
echo "   Битрикс CDN Server - Валидация"
echo "=========================================="
echo ""

# 1. Проверка Docker Compose
echo -e "${BLUE}1. Docker Compose Configuration${NC}"
echo "----------------------------------------"

if command -v docker-compose &> /dev/null; then
    docker-compose -f docker-compose.yml config > /dev/null 2>&1
    check_result $? "docker-compose.yml syntax"
    
    docker-compose -f docker-compose.dev.yml config > /dev/null 2>&1
    check_result $? "docker-compose.dev.yml syntax"
    
    docker-compose -f docker-compose.local.yml config > /dev/null 2>&1
    check_result $? "docker-compose.local.yml syntax"
else
    echo -e "${YELLOW}⚠ Docker Compose не установлен${NC}"
fi

echo ""

# 2. Проверка NGINX конфигураций
echo -e "${BLUE}2. NGINX Configurations${NC}"
echo "----------------------------------------"

# Создаем временный контейнер для проверки NGINX
if command -v docker &> /dev/null; then
    # Проверяем основной nginx.conf
    docker run --rm -v $(pwd)/docker/nginx/nginx.conf:/etc/nginx/nginx.conf:ro \
        nginx:1.27-alpine nginx -t > /dev/null 2>&1
    check_result $? "docker/nginx/nginx.conf syntax"
    
    # Проверяем cdn.conf
    docker run --rm \
        -v $(pwd)/docker/nginx/nginx.conf:/etc/nginx/nginx.conf:ro \
        -v $(pwd)/docker/nginx/conf.d:/etc/nginx/conf.d:ro \
        nginx:1.27-alpine nginx -t > /dev/null 2>&1
    check_result $? "docker/nginx/conf.d/cdn.conf syntax"
else
    echo -e "${YELLOW}⚠ Docker не установлен для проверки NGINX${NC}"
fi

echo ""

# 3. Проверка Varnish VCL
echo -e "${BLUE}3. Varnish VCL Configuration${NC}"
echo "----------------------------------------"

if [ -f "docker/varnish/default.vcl" ]; then
    # Проверяем синтаксис VCL через Docker
    if command -v docker &> /dev/null; then
        docker run --rm -v $(pwd)/docker/varnish/default.vcl:/etc/varnish/default.vcl:ro \
            varnish:7.5-alpine varnishd -C -f /etc/varnish/default.vcl > /dev/null 2>&1
        check_result $? "docker/varnish/default.vcl syntax"
    else
        echo -e "${YELLOW}⚠ Docker не установлен для проверки Varnish${NC}"
    fi
else
    echo -e "${RED}❌ docker/varnish/default.vcl не найден${NC}"
    FAILED_CHECKS=$((FAILED_CHECKS + 1))
fi

echo ""

# 4. Проверка Python скриптов
echo -e "${BLUE}4. Python Scripts${NC}"
echo "----------------------------------------"

if command -v python3 &> /dev/null; then
    python3 -m py_compile docker/webp-converter/converter.py 2> /dev/null
    check_result $? "docker/webp-converter/converter.py syntax"
else
    echo -e "${YELLOW}⚠ Python3 не установлен${NC}"
fi

echo ""

# 5. Проверка Prometheus конфигурации
echo -e "${BLUE}5. Prometheus Configuration${NC}"
echo "----------------------------------------"

if [ -f "docker/prometheus/prometheus.yml" ]; then
    # Проверяем YAML синтаксис
    if command -v python3 &> /dev/null; then
        python3 -c "import yaml; yaml.safe_load(open('docker/prometheus/prometheus.yml'))" 2> /dev/null
        check_result $? "docker/prometheus/prometheus.yml YAML syntax"
    fi
    
    # Проверяем через promtool если доступен
    if command -v docker &> /dev/null; then
        docker run --rm -v $(pwd)/docker/prometheus:/prometheus:ro \
            prom/prometheus:v2.53.2 \
            promtool check config /prometheus/prometheus.yml > /dev/null 2>&1
        check_result $? "prometheus.yml configuration validity"
    fi
else
    echo -e "${RED}❌ docker/prometheus/prometheus.yml не найден${NC}"
    FAILED_CHECKS=$((FAILED_CHECKS + 1))
fi

echo ""

# 6. Проверка Bash скриптов
echo -e "${BLUE}6. Bash Scripts${NC}"
echo "----------------------------------------"

for script in docker-manage.sh monitoring/check-health.sh scripts/*.sh; do
    if [ -f "$script" ]; then
        bash -n "$script" 2> /dev/null
        check_result $? "$script syntax"
    fi
done

echo ""

# 7. Проверка структуры директорий
echo -e "${BLUE}7. Directory Structure${NC}"
echo "----------------------------------------"

# Проверяем критические директории
dirs=(
    "docker/nginx/conf.d"
    "docker/webp-converter"
    "docker/sshfs"
    "docker/prometheus"
    "docker/grafana"
    "docs"
    "logs"
    "scripts"
)

for dir in "${dirs[@]}"; do
    if [ -d "$dir" ]; then
        check_result 0 "Directory exists: $dir"
    else
        check_result 1 "Directory missing: $dir"
    fi
done

echo ""

# 8. Проверка переменных окружения
echo -e "${BLUE}8. Environment Variables${NC}"
echo "----------------------------------------"

if [ -f ".env.example" ]; then
    check_result 0 ".env.example exists"
    
    # Проверяем критические переменные
    required_vars=(
        "BITRIX_SERVER_IP"
        "BITRIX_SERVER_USER"
        "BITRIX_UPLOAD_PATH"
        "CDN_DOMAIN"
        "WEBP_QUALITY"
    )
    
    for var in "${required_vars[@]}"; do
        if grep -q "^$var=" .env.example; then
            check_result 0 "Variable defined: $var"
        else
            check_result 1 "Variable missing: $var"
        fi
    done
else
    check_result 1 ".env.example missing"
fi

echo ""

# 9. Проверка архитектуры (2 сервера)
echo -e "${BLUE}9. Two-Server Architecture Check${NC}"
echo "----------------------------------------"

# Проверяем что SSHFS настроен как read-only mount
if grep -q "ro" docker-compose.yml | grep -q "bitrix-files"; then
    check_result 0 "SSHFS mount configured as read-only"
else
    check_result 1 "SSHFS mount not properly configured as read-only"
fi

# Проверяем разделение путей
if grep -q "/var/cache/webp" docker-compose.yml && grep -q "/mnt/bitrix" docker-compose.yml; then
    check_result 0 "Separate paths for mount and cache"
else
    check_result 1 "Mount and cache paths not properly separated"
fi

echo ""

# 10. Проверка безопасности
echo -e "${BLUE}10. Security Configuration${NC}"
echo "----------------------------------------"

# Проверяем наличие SSH ключей
if [ -f "docker/ssh/bitrix_mount" ] || [ -f "docker/ssh/.gitkeep" ]; then
    check_result 0 "SSH key directory exists"
else
    check_result 1 "SSH key directory missing"
fi

# Проверяем rate limiting в NGINX
if grep -q "limit_req_zone" docker/nginx/nginx.conf; then
    check_result 0 "Rate limiting configured"
else
    check_result 1 "Rate limiting not configured"
fi

# Проверяем security headers
# ИСПРАВЛЕНО: Проверка security headers
if grep -q "X-Frame-Options" docker/nginx/conf.d/cdn.conf; then
    check_result 0 "Security headers configured"
else
    check_result 1 "Security headers missing"
fi

echo ""
echo "=========================================="
echo -e "${BLUE}РЕЗУЛЬТАТЫ ВАЛИДАЦИИ${NC}"
echo "=========================================="
echo -e "Всего проверок:    $TOTAL_CHECKS"
echo -e "${GREEN}Успешно:          $PASSED_CHECKS${NC}"
echo -e "${RED}Провалено:        $FAILED_CHECKS${NC}"
echo ""

if [ $FAILED_CHECKS -eq 0 ]; then
    echo -e "${GREEN}✅ ВСЕ ПРОВЕРКИ ПРОЙДЕНЫ УСПЕШНО!${NC}"
    echo "Проект готов к развертыванию на cdn.termokit.ru"
    exit 0
else
    echo -e "${RED}❌ ОБНАРУЖЕНЫ ПРОБЛЕМЫ!${NC}"
    echo "Исправьте ошибки перед развертыванием"
    exit 1
fi