FROM alpine:3.18

# Установка необходимых пакетов
RUN apk add --no-cache \
    bash \
    libwebp-tools \
    imagemagick \
    inotify-tools \
    findutils \
    coreutils \
    python3 \
    py3-pip \
    py3-pillow \
    redis

# Установка Python библиотек для продвинутой обработки
RUN pip3 install --no-cache-dir \
    redis \
    Pillow \
    watchdog

# Создание директорий
RUN mkdir -p /var/cache/webp \
    /var/log/converter \
    /app

# Копирование скриптов
COPY converter.py /app/converter.py
COPY entrypoint.sh /app/entrypoint.sh

# Установка прав
RUN chmod +x /app/entrypoint.sh \
    && chmod +x /app/converter.py

WORKDIR /app

# Запуск конвертера
ENTRYPOINT ["/app/entrypoint.sh"]
