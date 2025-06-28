#!/bin/bash
# ms - Точка входа для MiniStack CLI
# Версия 1.0.31

# Проверка, что используется bash
if [ -z "$BASH_VERSION" ]; then
    echo "ERROR: Скрипт должен выполняться в Bash, а не в sh"
    exit 1
fi

# Проверка наличия файлов перед их подключением
LIB_DIR="/usr/local/lib/minStack"
FILES=("config.sh" "core.sh" "nginx_utils.sh" "utils.sh" "stack_install.sh" "site_create.sh" "site_bulk_create.sh" "site_bulk_delete.sh" "site_delete.sh" "site_info.sh" "secure_ssl.sh" "clean_headers.sh" "show_info.sh")

for file in "${FILES[@]}"; do
    if [ ! -f "$LIB_DIR/$file" ]; then
        echo "ERROR: Файл $LIB_DIR/$file не найден"
        exit 1
    fi
done

. "$LIB_DIR/config.sh"
. "$LIB_DIR/core.sh"
. "$LIB_DIR/nginx_utils.sh"
. "$LIB_DIR/utils.sh"
. "$LIB_DIR/stack_install.sh"
. "$LIB_DIR/site_create.sh"
. "$LIB_DIR/site_bulk_create.sh"
. "$LIB_DIR/site_bulk_delete.sh"
. "$LIB_DIR/site_delete.sh"
. "$LIB_DIR/site_info.sh"
. "$LIB_DIR/secure_ssl.sh"
. "$LIB_DIR/clean_headers.sh"
. "$LIB_DIR/show_info.sh"

# Парсинг команд
case "$1" in
    stack)
        case "$2" in
            install) install_stack ;;
            *) log_message "error" "Укажите 'install' для команды stack"; show_help ;;
        esac
        ;;
    site)
        case "$2" in
            create) create_site "$3" "$4" "$5" "$6" "$7" ;;
            bulk) bulk_create_sites ;;
            bulk-delete) bulk_delete_sites ;;
            delete) delete_site "$3" ;;
            info) site_info "$3" ;;
            *) log_message "error" "Укажите 'create', 'bulk', 'bulk-delete', 'delete' или 'info'"; show_help ;;
        esac
        ;;
    secure)
        if [ "$2" = "--ssl" ]; then
            if [[ "$4" == "--letsencrypt" || "$4" == "--selfsigned" || -z "$4" ]]; then
                setup_ssl "$3" "$4"
            else
                log_message "error" "Неверный флаг для secure --ssl: $4. Используйте --letsencrypt или --selfsigned"
                show_help
            fi
        else
            log_message "error" "Укажите --ssl и домен"
            show_help
        fi
        ;;
    clean) clean_headers ;;
    info) show_info ;;
    help|--help|-h) show_help ;;
    *) log_message "error" "Неизвестная команда"; show_help ;;
esac
