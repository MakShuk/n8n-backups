#!/bin/bash

# Настройка переменных
BACKUP_DATE=$(date +"%Y-%m-%d_%H-%M-%S")
BACKUP_PATH="/backup"
DATA_PATH="/data/n8n"
REMOTE_PATH="webdav:/n8n-backups"
KEEP_DAYS=${BACKUP_KEEP_DAYS:-1}
CLOUD_KEEP_DAYS=${CLOUD_KEEP_DAYS:-30}

echo "=============================================="
echo "Запуск резервного копирования: ${BACKUP_DATE}"
echo "Локальное хранение: ${KEEP_DAYS} дней"
echo "Облачное хранение: ${CLOUD_KEEP_DAYS} дней"
echo "=============================================="

# Проверка существования конфигурации rclone
if [ ! -f /root/.config/rclone/rclone.conf ]; then
    echo "❌ Конфигурация rclone не найдена! Запускаем настройку..."
    # Создаем конфигурацию rclone заново
    rclone config create webdav webdav vendor=yandex url="${WEBDAV_URL}" user="${WEBDAV_USERNAME}" pass="${WEBDAV_PASSWORD}" --non-interactive

    echo "✅ Конфигурация rclone создана для ${WEBDAV_URL}"
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

# Проверка успешности загрузки
echo "Проверка наличия загруженного файла в облачном хранилище..."
if rclone ls ${REMOTE_PATH}/$(basename ${ARCHIVE_FILE}) &> /dev/null; then
    echo "✅ Файл успешно загружен и доступен в облачном хранилище."
else
    echo "❌ Файл не найден в облачном хранилище после загрузки!"
    exit 1
fi

# Ротация бэкапов в облачном хранилище
echo "=============================================="
echo "Ротация бэкапов в облачном хранилище..."
echo "Удаление файлов старше ${CLOUD_KEEP_DAYS} дней..."

# Получаем список всех бэкапов в облаке
CLOUD_FILES=$(rclone lsf ${REMOTE_PATH}/ --files-only 2>/dev/null | grep "^n8n-backup-" | sort)

if [ -n "$CLOUD_FILES" ]; then
    # Вычисляем дату отсечки (CLOUD_KEEP_DAYS дней назад)
    CUTOFF_DATE=$(date -d "-${CLOUD_KEEP_DAYS} days" +"%Y-%m-%d" 2>/dev/null || date -v-${CLOUD_KEEP_DAYS}d +"%Y-%m-%d")

    DELETED_COUNT=0
    while IFS= read -r file; do
        # Извлекаем дату из имени файла (формат: n8n-backup-YYYY-MM-DD_HH-MM-SS.tar.gz.enc)
        FILE_DATE=$(echo "$file" | sed -n 's/n8n-backup-\([0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}\).*/\1/p')

        if [ -n "$FILE_DATE" ]; then
            # Сравниваем даты
            if [[ "$FILE_DATE" < "$CUTOFF_DATE" ]]; then
                echo "  Удаление: $file (дата: $FILE_DATE)"
                rclone delete "${REMOTE_PATH}/${file}" --verbose 2>/dev/null
                if [ $? -eq 0 ]; then
                    ((DELETED_COUNT++))
                fi
            fi
        fi
    done <<< "$CLOUD_FILES"

    echo "✅ Удалено старых бэкапов из облака: ${DELETED_COUNT}"
else
    echo "ℹ️ Файлы для ротации в облаке не найдены."
fi

# Удаление старых локальных архивов
echo "=============================================="
echo "Ротация локальных бэкапов..."
echo "Удаление локальных архивов старше ${KEEP_DAYS} дней..."

LOCAL_DELETED=$(find ${BACKUP_PATH} -name "n8n-backup-*.tar.gz*" -type f -mtime +${KEEP_DAYS} -delete -print 2>/dev/null | wc -l)
echo "✅ Удалено старых локальных архивов: ${LOCAL_DELETED}"

# Показываем текущее состояние хранилищ
echo "=============================================="
echo "Текущее состояние хранилищ:"
echo "----------------------------------------------"
echo "Локальные файлы:"
ls -lh ${BACKUP_PATH}/n8n-backup-*.tar.gz* 2>/dev/null || echo "  (пусто)"
echo "----------------------------------------------"
echo "Файлы в облаке:"
rclone ls ${REMOTE_PATH}/ 2>/dev/null | head -10
CLOUD_COUNT=$(rclone ls ${REMOTE_PATH}/ 2>/dev/null | wc -l)
if [ "$CLOUD_COUNT" -gt 10 ]; then
    echo "  ... и ещё $((CLOUD_COUNT - 10)) файлов"
fi
echo "=============================================="

echo "=============================================="
echo "Резервное копирование успешно завершено!"
echo "Дата: ${BACKUP_DATE}"
echo "Файл: $(basename ${ARCHIVE_FILE})"
echo "=============================================="