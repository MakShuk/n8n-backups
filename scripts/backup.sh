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

# Копирование архива на WebDAV
echo "Копирование архива в облачное хранилище..."
echo "Используем команду: rclone copy ${BACKUP_PATH}/n8n-backup-${BACKUP_DATE}.tar.gz ${REMOTE_PATH}/ --verbose"
rclone copy ${BACKUP_PATH}/n8n-backup-${BACKUP_DATE}.tar.gz ${REMOTE_PATH}/ --verbose

if [ $? -ne 0 ]; then
    echo "❌ Ошибка при копировании архива в облачное хранилище."
    echo "Повторная попытка с явным указанием конфигурации..."
    rclone copy --config=/root/.config/rclone/rclone.conf ${BACKUP_PATH}/n8n-backup-${BACKUP_DATE}.tar.gz ${REMOTE_PATH}/ --verbose
    
    if [ $? -ne 0 ]; then
        echo "❌ Повторная попытка также завершилась неудачей."
        exit 1
    fi
fi
echo "✅ Архив успешно скопирован в облачное хранилище."

# Удаление старых архивов на сервере
echo "Удаление локальных архивов старше ${KEEP_DAYS} дней..."
find ${BACKUP_PATH} -name "n8n-backup-*.tar.gz" -type f -mtime +${KEEP_DAYS} -delete
echo "✅ Старые локальные архивы удалены."

# Проверка успешности загрузки
echo "Проверка наличия загруженного файла в облачном хранилище..."
if rclone ls ${REMOTE_PATH}/n8n-backup-${BACKUP_DATE}.tar.gz &> /dev/null; then
    echo "✅ Файл успешно загружен и доступен в облачном хранилище."
else
    echo "❌ Файл не найден в облачном хранилище после загрузки!"
    exit 1
fi

echo "=============================================="
echo "Резервное копирование успешно завершено!"
echo "Дата: ${BACKUP_DATE}"
echo "Файл: n8n-backup-${BACKUP_DATE}.tar.gz"
echo "=============================================="

# Очистка папки backup после завершения
echo "Очистка папки резервных копий..."
rm -f ${BACKUP_PATH}/n8n-backup-*.tar.gz
echo "✅ Папка резервных копий успешно очищена."