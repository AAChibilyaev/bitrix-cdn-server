#!/bin/bash
# Автоматический установщик CDN сервера для Битрикс
# /scripts/install.sh
# Author: Chibilyaev Alexandr <info@aachibilyaev.com>
# Company: AAChibilyaev LTD

set -e  # Останавливаться при ошибках

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ИСПРАВЛЕНО: Конфигурация из config.sh
if [ -f "config.sh" ]; then
    source config.sh
else
    echo -e "${RED}config.sh not found. Copy from config.sh.example and edit${NC}"
    exit 1
fi

# Функции вывода
print_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Проверка root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root"
    fi
}

# Запрос конфигурации
request_config() {
    echo "========================================="
    echo "CDN Server Installation for Bitrix"
    echo "========================================="
    echo ""
    
    if [ -z "$BITRIX_SERVER_IP" ]; then
        read -p "Enter Bitrix server IP: " BITRIX_SERVER_IP
    fi
    
    if [ -z "$BITRIX_SERVER_USER" ]; then
        read -p "Enter SSH user for Bitrix server: " BITRIX_SERVER_USER
    fi
    
    if [ -z "$CDN_DOMAIN" ]; then
        read -p "Enter CDN domain (e.g., cdn.example.com): " CDN_DOMAIN
    fi
    
    if [ -z "$ADMIN_EMAIL" ]; then
        read -p "Enter admin email for alerts: " ADMIN_EMAIL
    fi
    
    echo ""
    echo "Configuration:"
    echo "  Bitrix Server: $BITRIX_SERVER_USER@$BITRIX_SERVER_IP"
    echo "  Bitrix Path: $BITRIX_UPLOAD_PATH"
    echo "  CDN Domain: $CDN_DOMAIN"
    echo "  Admin Email: $ADMIN_EMAIL"
    echo ""
    
    read -p "Is this correct? (y/n): " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_error "Installation cancelled"
    fi
}

# Установка пакетов
install_packages() {
    print_step "Installing required packages..."
    
    apt update
    apt install -y \
        nginx \
        webp \
        sshfs \
        imagemagick \
        curl \
        htop \
        nano \
        certbot \
        python3-certbot-nginx \
        mailutils \
        bc \
        net-tools \
        dnsutils
    
    print_success "Packages installed"
}

# Настройка SSH ключей
setup_ssh_keys() {
    print_step "Setting up SSH keys..."
    
    if [ ! -f /root/.ssh/bitrix_mount ]; then
        ssh-keygen -t rsa -b 4096 -f /root/.ssh/bitrix_mount -N ""
        print_success "SSH key generated"
    else
        print_warning "SSH key already exists"
    fi
    
    echo ""
    echo "Please add this public key to $BITRIX_SERVER_USER@$BITRIX_SERVER_IP:~/.ssh/authorized_keys"
    echo ""
    cat /root/.ssh/bitrix_mount.pub
    echo ""
    read -p "Press Enter when done..."
    
    # Тест подключения
    print_step "Testing SSH connection..."
    if ssh -o ConnectTimeout=5 -o BatchMode=yes -i /root/.ssh/bitrix_mount \
        "$BITRIX_SERVER_USER@$BITRIX_SERVER_IP" "echo 'SSH OK'" | grep -q "SSH OK"; then
        print_success "SSH connection successful"
    else
        print_error "SSH connection failed. Please check the key setup"
    fi
}

# Создание директорий
create_directories() {
    print_step "Creating directory structure..."
    
    mkdir -p /mnt/bitrix
    mkdir -p /var/cache/webp
    mkdir -p /var/log/cdn
    mkdir -p /usr/local/bin
    
    chown -R www-data:www-data /var/cache/webp
    chown -R www-data:www-data /var/log/cdn
    
    print_success "Directories created"
}

# Установка скриптов
install_scripts() {
    print_step "Installing scripts..."
    
    # Обновление конфигурации в скриптах
    sed -i "s/REMOTE_USER=\"user\"/REMOTE_USER=\"$BITRIX_SERVER_USER\"/" scripts/mount.sh
    sed -i "s/REMOTE_HOST=\"bitrix-server-ip\"/REMOTE_HOST=\"$BITRIX_SERVER_IP\"/" scripts/mount.sh
    sed -i "s/REMOTE_PATH=\".*\"/REMOTE_PATH=\"$BITRIX_UPLOAD_PATH\"/" scripts/mount.sh
    
    sed -i "s/ALERT_EMAIL=\".*\"/ALERT_EMAIL=\"$ADMIN_EMAIL\"/" monitoring/check-health.sh
    sed -i "s/bitrix_host=\"bitrix-server-ip\"/bitrix_host=\"$BITRIX_SERVER_IP\"/" monitoring/check-health.sh
    
    # Копирование скриптов
    cp scripts/mount.sh /usr/local/bin/mount-bitrix.sh
    cp scripts/webp-convert.sh /usr/local/bin/webp-convert.sh
    cp monitoring/check-health.sh /usr/local/bin/check-cdn-health.sh
    
    chmod +x /usr/local/bin/mount-bitrix.sh
    chmod +x /usr/local/bin/webp-convert.sh
    chmod +x /usr/local/bin/check-cdn-health.sh
    
    print_success "Scripts installed"
}

# Настройка systemd
setup_systemd() {
    print_step "Setting up systemd service..."
    
    # Обновление конфигурации в сервисе
    sed -i "s/user@bitrix-server/$BITRIX_SERVER_USER@$BITRIX_SERVER_IP/" systemd/sshfs-mount.service
    sed -i "s|/path/to/bitrix/upload|$BITRIX_UPLOAD_PATH|" systemd/sshfs-mount.service
    
    cp systemd/sshfs-mount.service /etc/systemd/system/
    
    systemctl daemon-reload
    systemctl enable sshfs-mount
    systemctl start sshfs-mount
    
    sleep 3
    
    # Проверка
    if mountpoint -q /mnt/bitrix; then
        print_success "Mount service started successfully"
    else
        print_error "Mount service failed to start"
    fi
}

# Настройка NGINX
setup_nginx() {
    print_step "Setting up NGINX..."
    
    # Обновление домена в конфиге
    sed -i "s/cdn.yourdomain.ru/$CDN_DOMAIN/g" nginx/sites-available/cdn.conf
    
    # Копирование конфига
    cp nginx/sites-available/cdn.conf /etc/nginx/sites-available/
    ln -sf /etc/nginx/sites-available/cdn.conf /etc/nginx/sites-enabled/
    
    # Удаление default сайта если есть
    rm -f /etc/nginx/sites-enabled/default
    
    # Проверка конфигурации
    if nginx -t; then
        systemctl restart nginx
        print_success "NGINX configured and started"
    else
        print_error "NGINX configuration error"
    fi
}

# Настройка cron
setup_cron() {
    print_step "Setting up cron jobs..."
    
    # Добавление заданий в cron
    (crontab -l 2>/dev/null; echo "*/5 * * * * /usr/local/bin/mount-bitrix.sh") | crontab -
    (crontab -l 2>/dev/null; echo "0 3 * * * /usr/local/bin/webp-convert.sh cleanup 30") | crontab -
    (crontab -l 2>/dev/null; echo "0 4 * * * /usr/local/bin/webp-convert.sh sync") | crontab -
    (crontab -l 2>/dev/null; echo "*/10 * * * * /usr/local/bin/check-cdn-health.sh > /dev/null 2>&1") | crontab -
    
    print_success "Cron jobs configured"
}

# Настройка SSL
setup_ssl() {
    print_step "Setting up SSL certificate..."
    
    echo ""
    echo "Do you want to set up SSL certificate now? (requires domain to be pointed to this server)"
    read -p "Setup SSL? (y/n): " -n 1 -r
    echo ""
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        certbot --nginx -d "$CDN_DOMAIN"
        print_success "SSL certificate configured"
    else
        print_warning "SSL setup skipped. Run 'certbot --nginx -d $CDN_DOMAIN' later"
    fi
}

# Оптимизация системы
optimize_system() {
    print_step "Optimizing system settings..."
    
    # Sysctl оптимизации
    cat >> /etc/sysctl.conf <<EOF

# CDN Server Optimizations
net.core.somaxconn = 65535
net.ipv4.tcp_max_tw_buckets = 1440000
net.core.netdev_max_backlog = 16384
net.ipv4.tcp_max_syn_backlog = 8192
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_keepalive_time = 300
net.ipv4.tcp_keepalive_probes = 5
net.ipv4.tcp_keepalive_intvl = 15
fs.file-max = 2097152
EOF
    
    sysctl -p
    
    # Лимиты
    cat >> /etc/security/limits.conf <<EOF

# CDN Server Limits
www-data soft nofile 65535
www-data hard nofile 65535
www-data soft nproc 32768
www-data hard nproc 32768
EOF
    
    print_success "System optimized"
}

# Тестирование
run_tests() {
    print_step "Running tests..."
    
    echo ""
    echo "1. Testing mount point..."
    if ls /mnt/bitrix > /dev/null 2>&1; then
        echo "   ✓ Mount is working"
    else
        echo "   ✗ Mount failed"
    fi
    
    echo "2. Testing NGINX..."
    if curl -s -o /dev/null -w "%{http_code}" "http://localhost" | grep -q "200\|301\|302"; then
        echo "   ✓ NGINX is responding"
    else
        echo "   ✗ NGINX not responding"
    fi
    
    echo "3. Testing WebP conversion..."
    test_image=$(find /mnt/bitrix -type f \( -name "*.jpg" -o -name "*.png" \) | head -1)
    if [ -n "$test_image" ]; then
        if /usr/local/bin/webp-convert.sh convert "$test_image" > /dev/null 2>&1; then
            echo "   ✓ WebP conversion working"
        else
            echo "   ✗ WebP conversion failed"
        fi
    else
        echo "   ⚠ No test images found"
    fi
    
    echo ""
    print_success "Basic tests completed"
}

# Вывод инструкций
print_instructions() {
    echo ""
    echo "========================================="
    echo "Installation Complete!"
    echo "========================================="
    echo ""
    echo "Next steps:"
    echo ""
    echo "1. Configure DNS:"
    echo "   Point $CDN_DOMAIN to $(curl -s ifconfig.me)"
    echo ""
    echo "2. Configure Bitrix:"
    echo "   Add to /bitrix/php_interface/init.php:"
    echo '   define("BX_IMG_SERVER", "https://'$CDN_DOMAIN'");'
    echo ""
    echo "3. Test the CDN:"
    echo "   https://$CDN_DOMAIN/path/to/image.jpg"
    echo ""
    echo "4. Monitor health:"
    echo "   /usr/local/bin/check-cdn-health.sh"
    echo ""
    echo "5. View logs:"
    echo "   tail -f /var/log/cdn/convert.log"
    echo "   tail -f /var/log/nginx/error.log"
    echo ""
    echo "Documentation:"
    echo "   /root/bitrix-cdn/docs/INSTALL.md"
    echo "   /root/bitrix-cdn/docs/TROUBLESHOOTING.md"
    echo ""
}

# Главная функция
main() {
    check_root
    request_config
    
    echo ""
    print_step "Starting installation..."
    echo ""
    
    install_packages
    setup_ssh_keys
    create_directories
    install_scripts
    setup_systemd
    setup_nginx
    setup_cron
    optimize_system
    setup_ssl
    run_tests
    
    print_instructions
}

# Запуск
main
