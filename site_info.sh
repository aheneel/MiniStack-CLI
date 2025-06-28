# site_info.sh - Команда для отображения информации о сайте в MiniStack CLI
# Версия 1.0.31

site_info() {
    clean_old_logs
    DOMAIN=$1
    if [ -z "$DOMAIN" ]; then
        log_message "error" "Укажите домен, например: sudo ms site info example.com"
        exit 1
    fi
    ORIGINAL_DOMAIN="$DOMAIN"
    DOMAIN=$(convert_to_punycode "$DOMAIN")
    log_message "info" "Информация о сайте $ORIGINAL_DOMAIN (Punycode: $DOMAIN)..." "start_operation"
    if ! grep -q "Site: $ORIGINAL_DOMAIN" "$SITE_CREDENTIALS"; then
        log_message "error" "Сайт $ORIGINAL_DOMAIN не найден в $SITE_CREDENTIALS"
        exit 1
    fi
    CREDENTIALS=$(grep -A11 "Site: $ORIGINAL_DOMAIN" "$SITE_CREDENTIALS" | sed 's/^/  /')
    echo -e "$CREDENTIALS"
    SUCCESS_COUNT=1
    ERROR_COUNT=0
    log_message "info" "Информация о сайте отображена" "end_operation" "Информация о сайте отображена"
}