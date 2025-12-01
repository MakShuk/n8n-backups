#!/bin/bash

# Функция для маскирования конфиденциальных данных
mask_sensitive() {
    local value="$1"
    local visible_chars="${2:-3}"
    if [ ${#value} -le $((visible_chars * 2)) ]; then
        echo "***"
    else
        echo "${value:0:$visible_chars}***${value: -$visible_chars}"
    fi
}

# Выводим переменные окружения для отладки (с маскированием паролей)
echo "=============================================="
echo "Проверка переменных окружения:"
echo "WEBDAV_URL: ${WEBDAV_URL}"
echo "WEBDAV_USERNAME: $(mask_sensitive "${WEBDAV_USERNAME}" 4)"
echo "WEBDAV_PASSWORD: [СКРЫТО]"
echo "=============================================="

# Создаем директорию для конфигурации rclone
mkdir -p /root/.config/rclone

# Создаем конфигурацию rclone с помощью команды config create
echo "Создание конфигурации rclone..."
rclone config create webdav webdav vendor=other url="${WEBDAV_URL}" user="${WEBDAV_USERNAME}" pass="${WEBDAV_PASSWORD}" --non-interactive

# Выводим созданную конфигурацию для проверки (без пароля)
echo "=============================================="
echo "Конфигурация rclone создана для:"
echo "  - URL: ${WEBDAV_URL}"
echo "  - Пользователь: $(mask_sensitive "${WEBDAV_USERNAME}" 4)"
echo "=============================================="

# Выводим версию rclone для отладки
echo "Версия rclone:"
rclone --version

# Проверяем конфигурацию rclone
echo "=============================================="
echo "Тестирование подключения к WebDAV..."
echo "=============================================="

# Детальная отладка подключения
echo "Выполняю подробную диагностику..."
RCLONE_DEBUG_OUTPUT=$(rclone lsd webdav: --verbose 2>&1)
RCLONE_EXIT_CODE=$?

if [ $RCLONE_EXIT_CODE -eq 0 ]; then
    echo "✅ Подключение к WebDAV успешно установлено!"
    echo "URL: ${WEBDAV_URL}"
    echo "Пользователь: $(mask_sensitive "${WEBDAV_USERNAME}" 4)"

    # Проверяем наличие директории для бэкапов
    echo "=============================================="
    echo "Проверка директории для бэкапов..."
    if rclone ls webdav:/n8n-backups --verbose &> /dev/null; then
        echo "✅ Директория для бэкапов доступна."
    else
        echo "⚠️ Директория для бэкапов не найдена. Создаю директорию..."
        rclone mkdir webdav:/n8n-backups --verbose
        if [ $? -eq 0 ]; then
            echo "✅ Директория успешно создана."
        else
            echo "❌ Ошибка при создании директории."
            exit 1
        fi
    fi

    # Проверяем доступность для записи
    echo "=============================================="
    echo "Проверка прав на запись..."
    TEST_FILE="/tmp/webdav_test_file"
    echo "test" > ${TEST_FILE}
    if rclone copy ${TEST_FILE} webdav:/n8n-backups/test_file --verbose; then
        echo "✅ Запись в WebDAV работает корректно."
        rclone delete webdav:/n8n-backups/test_file --verbose
        echo "✅ Тестовый файл удален."
    else
        echo "❌ Ошибка записи в WebDAV."
        exit 1
    fi

    echo "=============================================="
    echo "Содержимое директории бэкапов:"
    rclone ls webdav:/n8n-backups --verbose
    echo "=============================================="
else
    echo "❌ Ошибка подключения к WebDAV!"
    echo "Код ошибки: ${RCLONE_EXIT_CODE}"
    echo "Детали ошибки:"
    echo "${RCLONE_DEBUG_OUTPUT}"

    echo "=============================================="
    echo "Пробуем альтернативную конфигурацию для Яндекс.Диска..."

    # Пробуем создать конфигурацию для Яндекс.Диска
    rclone config delete webdav --non-interactive
    rclone config create webdav webdav vendor=yandex url="${WEBDAV_URL}" user="${WEBDAV_USERNAME}" pass="${WEBDAV_PASSWORD}" --non-interactive

    echo "Тестирование с vendor=yandex:"
    rclone lsd webdav: --verbose
    ALT_EXIT_CODE=$?

    if [ $ALT_EXIT_CODE -eq 0 ]; then
        echo "✅ Подключение успешно с vendor=yandex!"
    else
        echo "❌ Альтернативные конфигурации не работают."

        # Попробуем ещё один вариант с явным указанием plaintext пароля
        echo "Пробуем третий вариант конфигурации..."
        rclone config delete webdav --non-interactive

        # Создаем явную конфигурацию с параметрами
        cat > /root/.config/rclone/rclone.conf << EOF
[webdav]
type = webdav
url = ${WEBDAV_URL}
vendor = othe
user = ${WEBDAV_USERNAME}
pass = $(echo -n ${WEBDAV_PASSWORD})
EOF

        echo "Тестирование с явным паролем:"
        rclone lsd webdav: --verbose
        THIRD_EXIT_CODE=$?

        if [ $THIRD_EXIT_CODE -eq 0 ]; then
            echo "✅ Третий вариант конфигурации работает!"
        else
            echo "❌ Все варианты конфигурации не работают."
            echo "=============================================="
            echo "Проверяем доступность ${WEBDAV_URL}:"
            curl -I ${WEBDAV_URL}
            echo "=============================================="
            echo "Проверьте правильность переданных параметров."
            exit 1
        fi
    fi
fi
