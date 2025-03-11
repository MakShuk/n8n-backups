#!/bin/bash

# Настройка переменных
BACKUP_DATE=$(date +"%Y-%m-%d_%H-%M-%S")
BACKUP_PATH="/backup"
DATA_PATH="/data/n8n"
REMOTE_PATH="webdav:/n8n-backups"
KEEP_DAYS=${BACKUP_KEEP_DAYS:-7}

echo "=============================================="
echo "Запуск резервного копирования: ${BACKUP_DATE}"
echo "=============================================="

# Проверка существования конфигурации rclone
if [ ! -f /root/.config/rclone/rclone.conf ]; then
    echo "❌ Конфигурация rclone не найдена! Запускаем настройку..."
    # Создаем конфигурацию rclone заново
    rclone config create webdav webdav vendor=yandex url="${WEBDAV_URL}" user="${WEBDAV_USERNAME}" pass="${WEBDAV_PASSWORD}" --non-interactive
    
    echo "Проверка созданной конфигурации:"
    rclone config show webdav
fi

# Создание локального архива
echo "Создание архива данных..."
tar -czf ${BACKUP_PATH}/n8n-backup-${BACKUP_DATE}.tar.gz -C ${DATA_PATH} .
if [ $? -ne 0 ]; then
    echo "❌ Ошибка при создании архива."
    exit 1
fi
echo "✅ Архив создан: n8n-backup-${BACKUP_DATE}.tar.gz"

# Задание переменной архива
ARCHIVE_FILE="${BACKUP_PATH}/n8n-backup-${BACKUP_DATE}.tar.gz"

# Если установлен пароль для архива, зашифруем архив
if [ -n "$ARCHIVE_PASSWORD" ]; then
    # Проверка на наличие openssl
    if ! command -v openssl >/dev/null 2>&1; then
         echo "openssl не найден. Пытаемся установить его..."
         apk update && apk add --no-cache openssl
         if ! command -v openssl >/dev/null 2>&1; then
             echo "❌ Не удалось установить openssl."
             exit 1
         fi
    fi
    echo "Обнаружен ARCHIVE_PASSWORD, шифрование архива..."
    openssl enc -aes-256-cbc -salt -pbkdf2 -in "$ARCHIVE_FILE" -out "${ARCHIVE_FILE}.enc" -pass pass:"$ARCHIVE_PASSWORD"
    if [ $? -ne 0 ]; then
         echo "❌ Ошибка при шифровании архива."
         exit 1
    fi
    rm "$ARCHIVE_FILE"
    ARCHIVE_FILE="${ARCHIVE_FILE}.enc"
    echo "✅ Архив зашифрован паролем."
fi

# Копирование архива на WebDAV
echo "Копирование архива в облачное хранилище..."
echo "Используем команду: rclone copy ${ARCHIVE_FILE} ${REMOTE_PATH}/ --verbose"
rclone copy ${ARCHIVE_FILE} ${REMOTE_PATH}/ --verbose

if [ $? -ne 0 ]; then
    echo "❌ Ошибка при копировании архива в облачное хранилище."
    echo "Повторная попытка с явным указанием конфигурации..."
    rclone copy --config=/root/.config/rclone/rclone.conf ${ARCHIVE_FILE} ${REMOTE_PATH}/ --verbose
    
    if [ $? -ne 0 ]; then
        echo "❌ Повторная попытка также завершилась неудачей."
        exit 1
    fi
fi
echo "✅ Архив успешно скопирован в облачное хранилище."

# Удаление старых архивов на сервере
echo "Удаление локальных архивов старше ${KEEP_DAYS} дней..."
find ${BACKUP_PATH} -name "n8n-backup-*.tar.gz*" -type f -mtime +${KEEP_DAYS} -delete
echo "✅ Старые локальные архивы удалены."

# Проверка успешности загрузки
echo "Проверка наличия загруженного файла в облачном хранилище..."
if rclone ls ${REMOTE_PATH}/$(basename ${ARCHIVE_FILE}) &> /dev/null; then
    echo "✅ Файл успешно загружен и доступен в облачном хранилище."
else
    echo "❌ Файл не найден в облачном хранилище после загрузки!"
    exit 1
fi

echo "=============================================="
echo "Резервное копирование успешно завершено!"
echo "Дата: ${BACKUP_DATE}"
echo "Файл: $(basename ${ARCHIVE_FILE})"
echo "=============================================="

# Очистка папки backup после завершения
echo "Очистка папки резервных копий..."
rm -f ${BACKUP_PATH}/n8n-backup-*.tar.gz*
echo "✅ Папка резервных копий успешно очищена."