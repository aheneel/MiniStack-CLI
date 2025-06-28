# ms - Точка входа для MiniStack CLI
# Версия 1.0.31

source /usr/local/lib/minStack/config.sh
source /usr/local/lib/minStack/core.sh
source /usr/local/lib/minStack/nginx_utils.sh
source /usr/local/lib/minStack/utils.sh
source /usr/local/lib/minStack/stack_install.sh
source /usr/local/lib/minStack/site_create.sh
source /usr/local/lib/minStack/site_bulk_create.sh
source /usr/local/lib/minStack/site_bulk_delete.sh
source /usr/local/lib/minStack/site_delete.sh
source /usr/local/lib/minStack/site_info.sh
source /usr/local/lib/minStack/secure_ssl.sh
source /usr/local/lib/minStack/clean_headers.sh
source /usr/local/lib/minStack/show_info.sh

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
            create) create_site "$3" "$4" "$5" "$6" ;;
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
