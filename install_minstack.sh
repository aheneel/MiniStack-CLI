#!/bin/bash

# install_minstack.sh - Установка MiniStack CLI из GitHub репозитория
# Устанавливает файлы, исправляет окончания строк, проверяет синтаксис, запускает sudo ms stack install и удаляет /root/MiniStack-CLI
# Версия 1.0.31

set -e

# Цвета для вывода
BLUE='\033[0;38;2;0;255;255m'
GREEN='\033[0;38;2;0;255;0m'
RED='\033[0;38;2;255;0;0m'
NC='\033[0m'

echo -e "${BLUE}=== MiniStack CLI Installation ===${NC}"

# Проверка свободного места на диске (>100MB)
if [ $(df -m / | tail -1 | awk '{print $4}') -lt 100 ]; then
    echo -e "${RED}Недостаточно места на диске (<100MB)${NC}"
    exit 1
fi

# Проверка наличия git
if ! command -v git >/dev/null 2>&1; then
    echo -e "${RED}Git не установлен. Устанавливаем...${NC}"
    sudo apt update
    sudo apt install -y git
fi

# Проверка наличия curl
if ! command -v curl >/dev/null 2>&1; then
    echo -e "${RED}Curl не установлен. Устанавливаем...${NC}"
    sudo apt update
    sudo apt install -y curl
fi

# Проверка наличия dos2unix
if ! command -v dos2unix >/dev/null 2>&1; then
    echo -e "${RED}dos2unix не установлен. Устанавливаем...${NC}"
    sudo apt update
    sudo apt install -y dos2unix
fi

# Директория для клонирования
REPO_DIR="/root/MiniStack-CLI"

# Удаляем старую папку, если существует
if [ -d "$REPO_DIR" ]; then
    echo -e "${BLUE}Удаляем старую папку $REPO_DIR...${NC}"
    sudo rm -rf "$REPO_DIR"
fi

# Клонирование репозитория
echo -e "${BLUE}Клонируем репозиторий...${NC}"
sudo git clone https://github.com/aheneel/MiniStack-CLI.git "$REPO_DIR"

# Проверка наличия файлов и синтаксиса, конвертация CRLF в LF
FILES=("ms" "config.sh" "core.sh" "nginx_utils.sh" "stack_install.sh" "site_create.sh" "site_bulk_create.sh" "site_bulk_delete.sh" "site_delete.sh" "site_info.sh" "secure_ssl.sh" "clean_headers.sh" "show_info.sh" "utils.sh")
for file in "${FILES[@]}"; do
    if [ ! -f "$REPO_DIR/$file" ]; then
        echo -e "${RED}Ошибка: файл $file не найден в репозитории${NC}"
        sudo rm -rf "$REPO_DIR"
        exit 1
    fi
    # Конвертация CRLF в LF
    sudo dos2unix "$REPO_DIR/$file" >/dev/null 2>&1
    # Проверка синтаксиса
    if ! bash -n "$REPO_DIR/$file"; then
        echo -e "${RED}Ошибка: синтаксическая ошибка в файле $file${NC}"
        sudo rm -rf "$REPO_DIR"
        exit 1
    fi
done

# Создание директорий
echo -e "${BLUE}Создаём директории...${NC}"
sudo mkdir -p /usr/local/lib/minStack

# Копирование файлов
echo -e "${BLUE}Копируем файлы...${NC}"
sudo cp "$REPO_DIR/ms" /usr/local/bin/ms
sudo cp "$REPO_DIR/config.sh" /usr/local/lib/minStack/config.sh
sudo cp "$REPO_DIR/core.sh" /usr/local/lib/minStack/core.sh
sudo cp "$REPO_DIR/nginx_utils.sh" /usr/local/lib/minStack/nginx_utils.sh
sudo cp "$REPO_DIR/stack_install.sh" /usr/local/lib/minStack/stack_install.sh
sudo cp "$REPO_DIR/site_create.sh" /usr/local/lib/minStack/site_create.sh
sudo cp "$REPO_DIR/site_bulk_create.sh" /usr/local/lib/minStack/site_bulk_create.sh
sudo cp "$REPO_DIR/site_bulk_delete.sh" /usr/local/lib/minStack/site_bulk_delete.sh
sudo cp "$REPO_DIR/site_delete.sh" /usr/local/lib/minStack/site_delete.sh
sudo cp "$REPO_DIR/site_info.sh" /usr/local/lib/minStack/site_info.sh
sudo cp "$REPO_DIR/secure_ssl.sh" /usr/local/lib/minStack/secure_ssl.sh
sudo cp "$REPO_DIR/clean_headers.sh" /usr/local/lib/minStack/clean_headers.sh
sudo cp "$REPO_DIR/show_info.sh" /usr/local/lib/minStack/show_info.sh
sudo cp "$REPO_DIR/utils.sh" /usr/local/lib/minStack/utils.sh

# Установка прав
echo -e "${BLUE}Настраиваем права доступа...${NC}"
sudo chmod +x /usr/local/bin/ms
sudo chmod 644 /usr/local/lib/minStack/*.sh

# Запуск установки стека
echo -e "${BLUE}Запускаем установку LEMP-стека...${NC}"
sudo ms stack install

# Удаление папки репозитория
echo -e "${BLUE}Удаляем папку $REPO_DIR...${NC}"
sudo rm -rf "$REPO_DIR"

echo -e "${GREEN}=== Установка MiniStack CLI завершена! ===${NC}"
