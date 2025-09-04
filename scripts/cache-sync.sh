#!/bin/bash
# Скрипт синхронизации кеша при изменении файлов на Битрикс сервере
# Запускается на CDN сервере для очистки устаревших WebP версий
# Author: Chibilyaev Alexandr <info@aachibilyaev.com>
# Company: AAChibilyaev LTD

set -e

# ИСПРАВЛЕНО: Конфигурация путей
MOUNT_DIR="/mnt/bitrix"
CACHE_DIR="/var/cache/webp"
LOG_FILE="/var/log/cdn/cache-sync.log"
REDIS_HOST="redis"
CHECK_INTERVAL=60  # Проверка каждые 60 секунд

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Функция логирования
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Функция проверки изменений
check_file_changes() {
    local original_file="$1"
    local relative_path="${original_file#$MOUNT_DIR}"
    local webp_file="$CACHE_DIR${relative_path}.webp"
    
    if [ -f "$webp_file" ]; then
        # Получаем время модификации файлов
        original_mtime=$(stat -c %Y "$original_file" 2>/dev/null || echo 0)
        webp_mtime=$(stat -c %Y "$webp_file" 2>/dev/null || echo 0)
        
        # Если оригинал новее WebP - удаляем WebP
        if [ "$original_mtime" -gt "$webp_mtime" ]; then
            log_message "Original updated: $relative_path"
            rm -f "$webp_file"
            
            # Очищаем запись в Redis если есть
            if command -v redis-cli &> /dev/null; then
                redis-cli -h "$REDIS_HOST" DEL "webp:$relative_path" &> /dev/null || true
            fi
            
            return 0  # Файл был обновлен
        fi
    fi
    
    return 1  # Файл не изменился
}

# Функция очистки orphaned WebP файлов
cleanup_orphaned() {
    local count=0
    
    log_message "Checking for orphaned WebP files..."
    
    # Находим все WebP файлы в кеше
    find "$CACHE_DIR" -name "*.webp" -type f | while read webp_file; do
        # ИСПРАВЛЕНО: Получаем путь к оригиналу
        relative_path="${webp_file#$CACHE_DIR}"
        relative_path="${relative_path%.webp}"
        original_file="$MOUNT_DIR$relative_path"
        
        # Если оригинал не существует - удаляем WebP
        if [ ! -f "$original_file" ]; then
            log_message "Removing orphaned WebP: $relative_path"
            rm -f "$webp_file"
            count=$((count + 1))
            
            # Очищаем из Redis
            if command -v redis-cli &> /dev/null; then
                redis-cli -h "$REDIS_HOST" DEL "webp:$relative_path" &> /dev/null || true
            fi
        fi
    done
    
    if [ $count -gt 0 ]; then
        log_message "Removed $count orphaned WebP files"
    fi
}

# Функция мониторинга в реальном времени (требует inotify-tools)
monitor_realtime() {
    if ! command -v inotifywait &> /dev/null; then
        echo -e "${YELLOW}inotify-tools не установлен. Установите для real-time мониторинга:${NC}"
        echo "apt-get install inotify-tools"
        return 1
    fi
    
    log_message "Starting real-time monitoring of $MOUNT_DIR"
    
    inotifywait -m -r "$MOUNT_DIR" \
        -e modify,create,delete,moved_to,moved_from \
        --format '%w%f %e' \
        --exclude '\.(webp|tmp|swp)$' | while read file event; do
        
        case $event in
            MODIFY|CREATE|MOVED_TO)
                if [[ "$file" =~ \.(jpg|jpeg|png|gif|bmp)$ ]]; then
                    check_file_changes "$file"
                fi
                ;;
            DELETE|MOVED_FROM)
                # При удалении оригинала - удаляем WebP
                relative_path="${file#$MOUNT_DIR/}"
                webp_file="$CACHE_DIR/${relative_path}.webp"
                if [ -f "$webp_file" ]; then
                    log_message "Original deleted, removing WebP: $relative_path"
                    rm -f "$webp_file"
                fi
                ;;
        esac
    done
}

# Функция периодической проверки
periodic_check() {
    log_message "Starting periodic check mode (interval: ${CHECK_INTERVAL}s)"
    
    while true; do
        updated_count=0
        checked_count=0
        
        # Проверяем все изображения
        find "$MOUNT_DIR" -type f \( -name "*.jpg" -o -name "*.jpeg" -o -name "*.png" -o -name "*.gif" -o -name "*.bmp" \) | while read original_file; do
            checked_count=$((checked_count + 1))
            
            if check_file_changes "$original_file"; then
                updated_count=$((updated_count + 1))
            fi
            
            # Показываем прогресс каждые 100 файлов
            if [ $((checked_count % 100)) -eq 0 ]; then
                echo -ne "\rChecked: $checked_count files..."
            fi
        done
        
        echo ""
        
        if [ $updated_count -gt 0 ]; then
            log_message "Updated $updated_count WebP files out of $checked_count checked"
        fi
        
        # Очистка orphaned файлов раз в час
        if [ $(($(date +%M) % 60)) -eq 0 ]; then
            cleanup_orphaned
        fi
        
        sleep "$CHECK_INTERVAL"
    done
}

# Функция ручной синхронизации
manual_sync() {
    log_message "Starting manual sync..."
    
    local updated=0
    local checked=0
    local start_time=$(date +%s)
    
    # Проверяем все файлы
    find "$MOUNT_DIR" -type f \( -name "*.jpg" -o -name "*.jpeg" -o -name "*.png" -o -name "*.gif" -o -name "*.bmp" \) | while read original_file; do
        checked=$((checked + 1))
        
        if check_file_changes "$original_file"; then
            updated=$((updated + 1))
        fi
        
        # Прогресс
        if [ $((checked % 50)) -eq 0 ]; then
            echo -ne "\rProgress: $checked files checked, $updated updated..."
        fi
    done
    
    echo ""
    
    # Очистка orphaned
    cleanup_orphaned
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    log_message "Sync completed: $checked files checked, $updated updated in ${duration}s"
    echo -e "${GREEN}✓ Sync completed${NC}"
    echo "Files checked: $checked"
    echo "Files updated: $updated"
    echo "Duration: ${duration}s"
}

# Функция показа статистики
show_stats() {
    echo -e "${YELLOW}=== Cache Sync Statistics ===${NC}"
    
    # Количество оригиналов
    original_count=$(find "$MOUNT_DIR" -type f \( -name "*.jpg" -o -name "*.jpeg" -o -name "*.png" -o -name "*.gif" -o -name "*.bmp" \) | wc -l)
    echo "Original images: $original_count"
    
    # Количество WebP в кеше
    webp_count=$(find "$CACHE_DIR" -name "*.webp" -type f | wc -l)
    echo "WebP cached: $webp_count"
    
    # Размер кеша
    cache_size=$(du -sh "$CACHE_DIR" 2>/dev/null | cut -f1)
    echo "Cache size: $cache_size"
    
    # Процент конвертированных
    if [ $original_count -gt 0 ]; then
        percent=$((webp_count * 100 / original_count))
        echo "Coverage: ${percent}%"
    fi
    
    # Последние изменения
    echo ""
    echo "Recent changes (last 10):"
    tail -n 10 "$LOG_FILE" | grep -E "(updated|deleted|orphaned)" || echo "No recent changes"
}

# Main
main() {
    # Создаем директории если нет
    mkdir -p "$(dirname "$LOG_FILE")"
    
    case "${1:-help}" in
        monitor)
            echo -e "${GREEN}Starting real-time monitoring...${NC}"
            monitor_realtime
            ;;
        periodic)
            echo -e "${GREEN}Starting periodic check mode...${NC}"
            periodic_check
            ;;
        sync)
            echo -e "${GREEN}Running manual sync...${NC}"
            manual_sync
            ;;
        cleanup)
            echo -e "${GREEN}Cleaning orphaned files...${NC}"
            cleanup_orphaned
            ;;
        stats)
            show_stats
            ;;
        help|*)
            echo "Cache Synchronization Script"
            echo "Usage: $0 [command]"
            echo ""
            echo "Commands:"
            echo "  monitor  - Real-time monitoring (requires inotify-tools)"
            echo "  periodic - Periodic check every ${CHECK_INTERVAL}s"
            echo "  sync     - One-time manual sync"
            echo "  cleanup  - Remove orphaned WebP files"
            echo "  stats    - Show cache statistics"
            echo "  help     - Show this help"
            ;;
    esac
}

# Запуск
main "$@"