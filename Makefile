# Makefile для управления CDN сервером
# Author: Chibilyaev Alexandr <info@aachibilyaev.com>
# Company: AAChibilyaev LTD

.PHONY: help install deploy test health clean backup restore

# Переменные
CONFIG_FILE = config.sh
BACKUP_DIR = /backup/cdn
DATE := $(shell date +%Y%m%d_%H%M%S)

help:
	@echo "CDN Server Management Commands:"
	@echo ""
	@echo "  make install    - Install CDN server (run on CDN server)"
	@echo "  make deploy IP=<server-ip> - Deploy to remote server"
	@echo "  make test       - Run all tests"
	@echo "  make health     - Check system health"
	@echo "  make clean      - Clean WebP cache"
	@echo "  make backup     - Backup configuration"
	@echo "  make restore    - Restore from backup"
	@echo "  make stats      - Show cache statistics"
	@echo "  make mount      - Remount SSHFS"
	@echo "  make unmount    - Unmount SSHFS"
	@echo "  make logs       - Show recent logs"
	@echo "  make monitor    - Start real-time monitoring"

install:
	@if [ ! -f $(CONFIG_FILE) ]; then \
		echo "Error: config.sh not found. Copy config.sh.example to config.sh and edit it."; \
		exit 1; \
	fi
	@chmod +x scripts/install.sh
	@./scripts/install.sh

deploy:
	@if [ -z "$(IP)" ]; then \
		echo "Error: Please specify IP address. Usage: make deploy IP=192.168.1.20"; \
		exit 1; \
	fi
	@chmod +x deploy.sh
	@./deploy.sh $(IP)

test:
	@echo "Running system tests..."
	@/usr/local/bin/check-cdn-health.sh

health:
	@/usr/local/bin/check-cdn-health.sh

clean:
	@echo "Cleaning WebP cache older than 7 days..."
	@/usr/local/bin/webp-convert.sh cleanup 7
	@echo "Cache cleaned"

backup:
	@echo "Creating backup..."
	@mkdir -p $(BACKUP_DIR)
	@tar -czf $(BACKUP_DIR)/cdn-backup-$(DATE).tar.gz \
		/etc/nginx/sites-available/cdn.conf \
		/etc/systemd/system/sshfs-mount.service \
		/usr/local/bin/mount-bitrix.sh \
		/usr/local/bin/webp-convert.sh \
		/usr/local/bin/check-cdn-health.sh \
		/root/.ssh/bitrix_mount* \
		2>/dev/null || true
	@echo "Backup created: $(BACKUP_DIR)/cdn-backup-$(DATE).tar.gz"

restore:
	@if [ -z "$(BACKUP)" ]; then \
		echo "Error: Please specify backup file. Usage: make restore BACKUP=cdn-backup-20240101_120000.tar.gz"; \
		exit 1; \
	fi
	@echo "Restoring from $(BACKUP_DIR)/$(BACKUP)..."
	@tar -xzf $(BACKUP_DIR)/$(BACKUP) -C /
	@systemctl daemon-reload
	@systemctl restart sshfs-mount
	@systemctl restart nginx
	@echo "Restore complete"

stats:
	@echo "=== CDN Cache Statistics ==="
	@echo "Cache directory: /var/cache/webp"
	@echo "Total WebP files: $$(find /var/cache/webp -type f -name '*.webp' 2>/dev/null | wc -l)"
	@echo "Cache size: $$(du -sh /var/cache/webp 2>/dev/null | cut -f1)"
	@echo ""
	@echo "=== Recent Conversions ==="
	@tail -5 /var/log/cdn/convert.log 2>/dev/null || echo "No recent conversions"

mount:
	@echo "Mounting SSHFS..."
	@systemctl restart sshfs-mount
	@sleep 2
	@if mountpoint -q /mnt/bitrix; then \
		echo "Mount successful"; \
	else \
		echo "Mount failed"; \
		exit 1; \
	fi

unmount:
	@echo "Unmounting SSHFS..."
	@fusermount -u /mnt/bitrix 2>/dev/null || true
	@systemctl stop sshfs-mount
	@echo "Unmounted"

logs:
	@echo "=== Recent NGINX Errors ==="
	@tail -10 /var/log/nginx/error.log 2>/dev/null || echo "No errors"
	@echo ""
	@echo "=== Recent Conversions ==="
	@tail -10 /var/log/cdn/convert.log 2>/dev/null || echo "No conversions"
	@echo ""
	@echo "=== Recent Mount Logs ==="
	@tail -10 /var/log/cdn/mount.log 2>/dev/null || echo "No mount logs"

monitor:
	@echo "Starting real-time monitoring (Ctrl+C to stop)..."
	@echo "Watching: NGINX access, errors, and conversions"
	@tail -f /var/log/nginx/cdn.access.log /var/log/nginx/error.log /var/log/cdn/convert.log 2>/dev/null

# Дополнительные команды для разработки
dev-test-webp:
	@echo "Testing WebP conversion..."
	@TEST_IMG=$$(find /mnt/bitrix -type f -name "*.jpg" | head -1); \
	if [ -n "$$TEST_IMG" ]; then \
		/usr/local/bin/webp-convert.sh convert "$$TEST_IMG"; \
	else \
		echo "No test images found"; \
	fi

dev-nginx-reload:
	@echo "Reloading NGINX configuration..."
	@nginx -t && nginx -s reload
	@echo "NGINX reloaded"

dev-clear-all-cache:
	@echo "WARNING: This will delete ALL WebP cache!"
	@read -p "Are you sure? (y/n): " confirm; \
	if [ "$$confirm" = "y" ]; then \
		rm -rf /var/cache/webp/*; \
		echo "All cache cleared"; \
	else \
		echo "Cancelled"; \
	fi
