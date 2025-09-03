FROM alpine:3.18

# Установка необходимых пакетов
RUN apk add --no-cache \
    bash \
    curl \
    docker-cli \
    jq \
    mailx \
    bc \
    ncurses

# Создание директорий
RUN mkdir -p /app /var/log/cdn

# Копирование скрипта проверки
COPY healthcheck.sh /app/healthcheck.sh

# Установка прав
RUN chmod +x /app/healthcheck.sh

WORKDIR /app

# Запуск проверки здоровья каждые 5 минут
CMD ["/bin/bash", "-c", "while true; do /app/healthcheck.sh; sleep ${CHECK_INTERVAL:-300}; done"]