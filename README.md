# n8n Backup

Этот проект предназначен для резервного копирования данных n8n. В проекте используются Docker Compose для создания необходимых сервисов и скрипты для автоматизации задач по бэкапу и настройке.

## Структура проекта

- **.gitignore** - файлы и каталоги, исключенные из контроля версий.
- **docker-compose.yml** - конфигурация Docker Compose для запуска необходимых сервисов.
- **backup/** - каталог для хранения резервных копий.
- **config/** - каталог для хранения конфигурационных файлов.
- **scripts/** - каталог со скриптами:
  - **backup.sh** - скрипт для создания резервных копий.
  - **setup.sh** - скрипт для первоначальной настройки проекта.
- **.env** - файл с настройками окружения.

## Пример шаблона .env

Создайте файл `.env` в корневом каталоге проекта и заполните его следующими переменными:

```
WEBDAV_URL=https://webdav.cloud.mail.ru
WEBDAV_USERNAME=user@bk.ru
WEBDAV_PASSWORD=pass
BACKUP_KEEP_DAYS=1
N8N_DATA_FOLDER=C:\User\.n8n

```

## Последовательность выполнения резервного копирования (скрипт backup.sh)

1. **Установка переменных**: Скрипт устанавливает дату резервного копирования, пути для хранения архива и данных, а также значение для периода хранения архивов.
2. **Проверка конфигурации rclone**: Если файл конфигурации rclone отсутствует, скрипт автоматически создает его с помощью команды `rclone config create` и выводит текущую конфигурацию.
3. **Создание локального архива**: Данные из указанного каталога архивируются с использованием команды `tar`, и архив сохраняется в указанном каталоге.
4. **Копирование архива на облачное хранилище**: Архив копируется на удаленное облачное хранилище через `rclone copy`. При неудаче выполняется повторная попытка с явным указанием конфигурационного файла.
5. **Проверка успешности загрузки**: Скрипт проверяет, доступен ли загруженный архив в облачном хранилище с помощью `rclone ls`.
6. **Очистка локальных архивов**: Удаляются архивы, старше заданного количества дней, и производится очистка папки резервных копий.

## Требования

- Docker и Docker Compose должны быть установлены на системе.
- Git для клонирования репозитория.

## Установка и запуск

1. Клонируйте репозиторий:
```
git clone <URL-репозитория>
```
2. Перейдите в каталог проекта:
```
cd n8n-backup
```
3. Запустите Docker Compose:
```
docker-compose up -d
```

## Лицензия

Проект распространяется под лицензией MIT.

