# secure_ssl.sh - Команда для настройки SSL в MiniStack CLI
# Версия 1.0.31

setup_ssl() {
    clean_old_logs
    DOMAIN=$1
    SUCCESS_COUNT=0
    ERROR_COUNT=0
    if [ -z "$DOMAIN" ]; then
        log_message "error" "Укажите домен, например: sudo ms secure --ssl example.com"
        exit 1
    fi
    ORIGINAL_DOMAIN="$DOMAIN"
    DOMAIN=$(convert_to_punycode "$DOMAIN")
    log_message "info" "Настраиваем SSL для $ORIGINAL_DOMAIN (Punycode: $DOMAIN)..." "start_operation"
    if ! command -v certbot >/dev/null 2>&1; then
        log_message "error" "Certbot не установлен"
        exit 1
    fi
    if [[ $(echo "$DOMAIN" | grep -o "\." | wc -l) -gt 1 ]]; then
        certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos --email admin@$ORIGINAL_DOMAIN
    else
        certbot --nginx -d "$DOMAIN" -d "www.$DOMAIN" --non-interactive --agree-tos --email admin@$ORIGINAL_DOMAIN
    fi
    if grep -q "listen 443 ssl" "/etc/nginx/sites-available/$DOMAIN"; then
        log_message "success" "SSL успешно установлен для $ORIGINAL_DOMAIN"
    else
        log_message "error" "SSL не установлен для $ORIGINAL_DOMAIN"
        ERROR_COUNT=1
        log_message "info" "Настройка SSL завершена" "end_operation" "Настройка SSL завершена"
        exit 1
    fi
    WEB_ROOT="/var/www/$DOMAIN/html"
    if [ -f "$WEB_ROOT/wp-config.php" ]; then
        DB_ROOT_PASS=$(get_db_root_pass)
        DB_NAME=$(echo "$DOMAIN" | tr . _)
        WP_URL="https://$DOMAIN"
        sudo -u www-data wp config set WP_SITEURL "$WP_URL" --allow-root --path="$WEB_ROOT" >/dev/null 2>&1
        sudo -u www-data wp option update siteurl "$WP_URL" --allow-root --path="$WEB_ROOT" >/dev/null 2>&1
        log_message "success" "WP_SITEURL обновлен на $WP_URL"
    fi
    if grep -q "Site: $ORIGINAL_DOMAIN" "$SITE_CREDENTIALS"; then
        sed -i "/Site: $ORIGINAL_DOMAIN/,/-------------------/{/SSL: .*/s//SSL: Enabled/}" "$SITE_CREDENTIALS" 2>/dev/null
        log_message "success" "Статус SSL обновлен в $SITE_CREDENTIALS"
    fi
    CONFIG_FILE="/etc/nginx/sites-available/$DOMAIN"
    if ! grep -q "Strict-Transport-Security" "$CONFIG_FILE"; then
        sed -i '/include \/etc\/nginx\/common\/security_headers.conf;/a\    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;' "$CONFIG_FILE"
    fi
    nginx -t && systemctl restart nginx
    check_service nginx
    log_message "success" "SSL и HSTS настроены для $ORIGINAL_DOMAIN!"
    SUCCESS_COUNT=1
    log_message "info" "Настройка SSL завершена" "end_operation" "Настройка SSL завершена"
}
