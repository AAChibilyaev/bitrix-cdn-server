#!/bin/bash
# Скрипт деплоя CDN конфигурации на удаленный сервер
# Запускать с локальной машины

# Конфигурация
REMOTE_SERVER=""  # IP адрес CDN сервера
REMOTE_USER="root"
REMOTE_PATH="/root/bitrix-cdn-server"

# Цвета
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

# Проверка параметров
if [ -z "$1" ]; then
    echo "Usage: $0 <cdn-server-ip>"
    echo "Example: $0 192.168.1.20"
    exit 1
fi

REMOTE_SERVER="$1"

echo "Deploying to $REMOTE_USER@$REMOTE_SERVER..."

# Создание архива
echo "Creating archive..."
tar -czf /tmp/bitrix-cdn-server.tar.gz \
    --exclude='.git' \
    --exclude='*.log' \
    --exclude='deploy.sh' \
    -C "$(dirname "$0")" .

# Копирование на сервер
echo "Copying to server..."
scp /tmp/bitrix-cdn-server.tar.gz "$REMOTE_USER@$REMOTE_SERVER:/tmp/"

# Распаковка и установка
echo "Installing on server..."
ssh "$REMOTE_USER@$REMOTE_SERVER" <<'ENDSSH'
    # Создание директории
    mkdir -p /root/bitrix-cdn-server
    
    # Распаковка
    cd /root/bitrix-cdn-server
    tar -xzf /tmp/bitrix-cdn-server.tar.gz
    
    # Установка прав
    chmod +x scripts/*.sh
    chmod +x monitoring/*.sh
    
    # Очистка
    rm /tmp/bitrix-cdn-server.tar.gz
    
    echo "Files deployed successfully"
    echo ""
    echo "Now run on the server:"
    echo "cd /root/bitrix-cdn-server"
    echo "./scripts/install.sh"
ENDSSH

# Очистка локального архива
rm /tmp/bitrix-cdn-server.tar.gz

echo -e "${GREEN}Deployment complete!${NC}"
echo ""
echo "Next steps:"
echo "1. SSH to $REMOTE_SERVER"
echo "2. cd /root/bitrix-cdn-server"
echo "3. Review config.sh.example and create config.sh"
echo "4. Run ./scripts/install.sh"
