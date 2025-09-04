#!/bin/bash
# Скрипт конвертации изображений в WebP
# /usr/local/bin/webp-convert.sh
# Author: Chibilyaev Alexandr <info@aachibilyaev.com>
# Company: AAChibilyaev LTD

# Конфигурация
MOUNT_DIR="/mnt/bitrix"
CACHE_DIR="/var/cache/webp"
LOG_FILE="/var/log/cdn/convert.log"
QUALITY=85
MAX_WIDTH=2048
MAX_HEIGHT=2048

# Функция логирования
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

# Создание директорий
create_dirs() {
    mkdir -p "$CACHE_DIR"
    mkdir -p "$(dirname "$LOG_FILE")"
}

# Получение MIME типа файла
get_mime_type() {
    file --mime-type -b "$1"
}

# ИСПРАВЛЕНО: Конвертация одного файла  
convert_to_webp() {
    local source_file="$1"
    local relative_path="${source_file#$MOUNT_DIR}"
    local cache_file="$CACHE_DIR${relative_path}.webp"
    local cache_dir="$(dirname "$cache_file")"
    
    # Проверяем существование исходного файла
    if [ ! -f "$source_file" ]; then
        log_message "ERROR: Source file not found: $source_file"
        return 1
    fi
    
    # Проверяем, не существует ли уже WebP версия
    if [ -f "$cache_file" ]; then
        # Проверяем, не новее ли оригинал
        if [ "$source_file" -nt "$cache_file" ]; then
            log_message "INFO: Original is newer, reconverting: $source_file"
        else
            log_message "INFO: WebP already exists and is up to date: $cache_file"
            echo "$cache_file"
            return 0
        fi
    fi
    
    # Создаем директорию для кеша если не существует
    mkdir -p "$cache_dir"
    
    # Определяем тип файла
    mime_type=$(get_mime_type "$source_file")
    
    case "$mime_type" in
        "image/jpeg"|"image/jpg")
            # Конвертация JPEG
            log_message "Converting JPEG: $source_file"
            cwebp -q "$QUALITY" -mt -af -m 6 \
                  -resize "$MAX_WIDTH" "$MAX_HEIGHT" \
                  "$source_file" -o "$cache_file" 2>/dev/null
            ;;
        
        "image/png")
            # Конвертация PNG (с сохранением прозрачности)
            log_message "Converting PNG: $source_file"
            cwebp -q "$QUALITY" -mt -af -m 6 -alpha_q 100 \
                  -resize "$MAX_WIDTH" "$MAX_HEIGHT" \
                  "$source_file" -o "$cache_file" 2>/dev/null
            ;;
        
        "image/gif")
            # GIF конвертируем через ImageMagick сначала в PNG
            log_message "Converting GIF: $source_file"
            temp_png="/tmp/$(basename "$source_file").png"
            convert "$source_file[0]" "$temp_png" 2>/dev/null
            cwebp -q "$QUALITY" -mt -af -m 6 \
                  -resize "$MAX_WIDTH" "$MAX_HEIGHT" \
                  "$temp_png" -o "$cache_file" 2>/dev/null
            rm -f "$temp_png"
            ;;
        
        *)
            log_message "ERROR: Unsupported file type: $mime_type for $source_file"
            return 1
            ;;
    esac
    
    # Проверяем успешность конвертации
    if [ -f "$cache_file" ] && [ -s "$cache_file" ]; then
        # Устанавливаем права
        chmod 644 "$cache_file"
        chown www-data:www-data "$cache_file"
        
        # Логируем размеры для статистики
        original_size=$(stat -c%s "$source_file")
        webp_size=$(stat -c%s "$cache_file")
        saved_percent=$(( (original_size - webp_size) * 100 / original_size ))
        
        log_message "SUCCESS: Converted $source_file ($original_size bytes) to WebP ($webp_size bytes), saved $saved_percent%"
        echo "$cache_file"
        return 0
    else
        log_message "ERROR: Failed to convert $source_file"
        return 1
    fi
}

# Массовая конвертация директории
convert_directory() {
    local dir="$1"
    local count=0
    
    log_message "Starting batch conversion for directory: $dir"
    
    # Находим все изображения
    find "$dir" -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.gif" \) | while read -r file; do
        convert_to_webp "$file"
        count=$((count + 1))
        
        # Пауза каждые 10 файлов чтобы не перегружать систему
        if [ $((count % 10)) -eq 0 ]; then
            sleep 0.1
        fi
    done
    
    log_message "Batch conversion completed. Processed $count files"
}

# Очистка старых файлов из кеша
cleanup_old_cache() {
    local days="${1:-30}"
    
    log_message "Cleaning cache files older than $days days"
    
    # Находим и удаляем старые WebP файлы
    find "$CACHE_DIR" -type f -name "*.webp" -atime +$days -delete
    
    # Удаляем пустые директории
    find "$CACHE_DIR" -type d -empty -delete
    
    log_message "Cache cleanup completed"
}

# Синхронизация кеша с оригиналами (удаление WebP для удаленных оригиналов)
sync_cache() {
    log_message "Starting cache synchronization"
    
    find "$CACHE_DIR" -type f -name "*.webp" | while read -r webp_file; do
        # Получаем путь к оригиналу
        relative_path="${webp_file#$CACHE_DIR}"
        original_file="$MOUNT_DIR${relative_path%.webp}"
        
        # Если оригинал не существует - удаляем WebP
        if [ ! -f "$original_file" ]; then
            log_message "Removing orphaned WebP: $webp_file (original not found)"
            rm -f "$webp_file"
        fi
    done
    
    log_message "Cache synchronization completed"
}

# Показать статистику кеша
show_stats() {
    echo "=== WebP Cache Statistics ==="
    echo "Cache directory: $CACHE_DIR"
    echo ""
    
    # Количество файлов
    webp_count=$(find "$CACHE_DIR" -type f -name "*.webp" 2>/dev/null | wc -l)
    echo "Total WebP files: $webp_count"
    
    # Размер кеша
    if [ "$webp_count" -gt 0 ]; then
        cache_size=$(du -sh "$CACHE_DIR" 2>/dev/null | cut -f1)
        echo "Cache size: $cache_size"
        
        # Средняя экономия
        total_original=0
        total_webp=0
        
        find "$CACHE_DIR" -type f -name "*.webp" | head -100 | while read -r webp_file; do
            relative_path="${webp_file#$CACHE_DIR}"
            original_file="$MOUNT_DIR${relative_path%.webp}"
            
            if [ -f "$original_file" ]; then
                original_size=$(stat -c%s "$original_file" 2>/dev/null || echo 0)
                webp_size=$(stat -c%s "$webp_file" 2>/dev/null || echo 0)
                total_original=$((total_original + original_size))
                total_webp=$((total_webp + webp_size))
            fi
        done
        
        if [ "$total_original" -gt 0 ]; then
            avg_saving=$(( (total_original - total_webp) * 100 / total_original ))
            echo "Average space saving: $avg_saving%"
        fi
    fi
    
    echo ""
    echo "=== Recent conversions ==="
    tail -5 "$LOG_FILE" 2>/dev/null || echo "No recent logs"
}

# Обработка аргументов командной строки
case "${1:-convert}" in
    convert)
        # Конвертация одного файла (путь передается как второй аргумент)
        if [ -n "$2" ]; then
            create_dirs
            convert_to_webp "$2"
        else
            echo "Usage: $0 convert <file_path>"
            exit 1
        fi
        ;;
    
    batch)
        # Массовая конвертация директории
        if [ -n "$2" ]; then
            create_dirs
            convert_directory "$2"
        else
            convert_directory "$MOUNT_DIR"
        fi
        ;;
    
    cleanup)
        # Очистка старых файлов
        create_dirs
        cleanup_old_cache "${2:-30}"
        ;;
    
    sync)
        # Синхронизация кеша
        create_dirs
        sync_cache
        ;;
    
    stats)
        # Показать статистику
        show_stats
        ;;
    
    *)
        echo "Usage: $0 {convert|batch|cleanup|sync|stats} [args]"
        echo ""
        echo "Commands:"
        echo "  convert <file>  - Convert single image to WebP"
        echo "  batch [dir]     - Batch convert directory (default: $MOUNT_DIR)"
        echo "  cleanup [days]  - Remove cache files older than N days (default: 30)"
        echo "  sync            - Remove WebP files for deleted originals"
        echo "  stats           - Show cache statistics"
        exit 1
        ;;
esac
