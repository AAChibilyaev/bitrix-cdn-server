#!/bin/bash
# Скрипт монтирования папки Битрикс через SSHFS
# /usr/local/bin/mount-bitrix.sh
# Author: Chibilyaev Alexandr <info@aachibilyaev.com>
# Company: AAChibilyaev LTD

# ИСПРАВЛЕНО: Конфигурация из переменных окружения
REMOTE_USER="${BITRIX_SERVER_USER:-www-data}"
REMOTE_HOST="${BITRIX_SERVER_IP:-192.168.1.10}"
REMOTE_PATH="${BITRIX_UPLOAD_PATH:-/var/www/bitrix/upload}"
LOCAL_MOUNT="/mnt/bitrix"
SSH_KEY="/root/.ssh/bitrix_mount"
LOG_FILE="/var/log/cdn/mount.log"

# Функция логирования
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

# Проверка, примонтирована ли папка
check_mount() {
    if mountpoint -q "$LOCAL_MOUNT"; then
        return 0
    else
        return 1
    fi
}

# Размонтирование если уже примонтировано
unmount_if_needed() {
    if check_mount; then
        log_message "Unmounting existing mount at $LOCAL_MOUNT"
        fusermount -u "$LOCAL_MOUNT"
        sleep 2
    fi
}

# Монтирование
mount_folder() {
    log_message "Attempting to mount $REMOTE_HOST:$REMOTE_PATH to $LOCAL_MOUNT"
    
    # Создаем директорию если не существует
    mkdir -p "$LOCAL_MOUNT"
    
    # Монтируем с оптимальными параметрами
    sshfs \
        -o allow_other \
        -o default_permissions \
        -o ro \
        -o cache=yes \
        -o kernel_cache \
        -o compression=no \
        -o large_read \
        -o big_writes \
        -o ServerAliveInterval=15 \
        -o ServerAliveCountMax=3 \
        -o reconnect \
        -o IdentityFile="$SSH_KEY" \
        -o StrictHostKeyChecking=no \
        "$REMOTE_USER@$REMOTE_HOST:$REMOTE_PATH" "$LOCAL_MOUNT"
    
    if [ $? -eq 0 ]; then
        log_message "Successfully mounted $REMOTE_HOST:$REMOTE_PATH"
        return 0
    else
        log_message "ERROR: Failed to mount $REMOTE_HOST:$REMOTE_PATH"
        return 1
    fi
}

# Проверка доступности удаленного сервера
check_remote_server() {
    ssh -o ConnectTimeout=5 -o BatchMode=yes -i "$SSH_KEY" \
        "$REMOTE_USER@$REMOTE_HOST" "echo 'OK'" > /dev/null 2>&1
    
    if [ $? -eq 0 ]; then
        return 0
    else
        log_message "ERROR: Cannot connect to remote server $REMOTE_HOST"
        return 1
    fi
}

# Основная логика
main() {
    # Создаем лог директорию если не существует
    mkdir -p $(dirname "$LOG_FILE")
    
    log_message "Starting mount check..."
    
    # Проверяем, примонтировано ли уже
    if check_mount; then
        log_message "Mount is active, checking if it's working..."
        
        # Проверяем, работает ли mount (пытаемся прочитать)
        if ls "$LOCAL_MOUNT" > /dev/null 2>&1; then
            log_message "Mount is working correctly"
            exit 0
        else
            log_message "Mount is stale, remounting..."
            unmount_if_needed
        fi
    fi
    
    # Проверяем доступность сервера
    if ! check_remote_server; then
        log_message "Remote server is not accessible"
        exit 1
    fi
    
    # Монтируем
    if mount_folder; then
        log_message "Mount completed successfully"
        
        # Проверяем что mount работает
        if ls "$LOCAL_MOUNT" > /dev/null 2>&1; then
            log_message "Mount verified and working"
            exit 0
        else
            log_message "ERROR: Mount created but not working"
            exit 1
        fi
    else
        log_message "ERROR: Mount failed"
        exit 1
    fi
}

# Запуск
main
