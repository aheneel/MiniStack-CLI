# site_create.sh - Команда для создания одного сайта в MiniStack CLI
# Версия 1.0.31

create_site() {
    clean_old_logs
    DOMAIN=$1
    TYPE=$2
    PHP_VERSION=$DEFAULT_PHP
    REDIRECT_MODE="none"
    SSL_TYPE=""
    SUCCESS_COUNT=0
    ERROR_COUNT=0

    # Проверка корректности домена и типа сайта
    if [ -z "$DOMAIN" ] || [ -z "$TYPE" ]; then
        log_message "error" "Укажите домен и тип сайта, например: sudo ms site create example.com --html [--php74|--php80|--php81|--php82|--php83] [--yes-www|--no-www] [--ssl-lets|--ssl-open]"
        exit 1
    fi

    if ! echo "$DOMAIN" | grep -qE '^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'; then
        log_message "error" "Невалидный домен: $DOMAIN. Домен должен содержать точку"
        exit 1
    fi

    if [[ "$TYPE" != "--html" && "$TYPE" != "--php" && "$TYPE" != "--wp" ]]; then
        log_message "error" "Неверный тип сайта: $TYPE. Используйте --html, --php или --wp"
        exit 1
    fi

    # Парсинг дополнительных аргументов
    shift 2
    VALID_FLAGS=("--php74" "--php80" "--php81" "--php82" "--php83" "--yes-www" "--no-www" "--ssl-lets" "--ssl-open")
    for arg in "$@"; do
        case "$arg" in
            --php74) PHP_VERSION="7.4" ;;
            --php80) PHP_VERSION="8.0" ;;
            --php81) PHP_VERSION="8.1" ;;
            --php82) PHP_VERSION="8.2" ;;
            --php83) PHP_VERSION="8.3" ;;
            --yes-www) REDIRECT_MODE="yes-www" ;;
            --no-www) REDIRECT_MODE="no-www" ;;
            --ssl-lets) SSL_TYPE="--letsencrypt" ;;
            --ssl-open) SSL_TYPE="--selfsigned" ;;
            *) log_message "warning" "Неверный аргумент: $arg. Игнорируем." ;;
        esac
    done

    ORIGINAL_DOMAIN="$DOMAIN"
    DOMAIN=$(convert_to_punycode "$DOMAIN")
    log_message "info" "Создаём сайт $ORIGINAL_DOMAIN (Punycode: $DOMAIN)..." "start_operation"
    if ! check_site_availability "$DOMAIN"; then
        ERROR_COUNT=1
        log_message "info" "Создание сайта завершено" "end_operation" "Создание сайта завершено"
        exit 1
    fi
    if ! check_site_exists "$DOMAIN"; then
        ERROR_COUNT=1
        log_message "info" "Создание сайта завершено" "end_operation" "Создание сайта завершено"
        exit 1
    fi

    WEB_ROOT="/var/www/$DOMAIN/html"
    CONFIG_FILE="/etc/nginx/sites-available/$DOMAIN"
    ENABLED_FILE="/etc/nginx/sites-enabled/$DOMAIN"

    mkdir -p "$WEB_ROOT"
    chown -R www-data:www-data "$WEB_ROOT"
    chmod -R 755 "$WEB_ROOT"

    DB_ROOT_PASS=$(get_db_root_pass)

    case $TYPE in
        --html)
            echo "<h1>Welcome to $ORIGINAL_DOMAIN</h1>" > "$WEB_ROOT/index.html"
            echo "<?php phpinfo();" > "$WEB_ROOT/index.php"
            generate_nginx_config "$DOMAIN" "$WEB_ROOT" "$PHP_VERSION" "$REDIRECT_MODE" "$TYPE"
            init_credentials
            echo "Site: $ORIGINAL_DOMAIN" >> "$SITE_CREDENTIALS" 2>/dev/null
            echo "Type: HTML" >> "$SITE_CREDENTIALS" 2>/dev/null
            echo "Path: $WEB_ROOT" >> "$SITE_CREDENTIALS" 2>/dev/null
            echo "PHP Version: $PHP_VERSION" >> "$SITE_CREDENTIALS" 2>/dev/null
            echo "SSL: Disabled" >> "$SITE_CREDENTIALS" 2>/dev/null
            echo "Redirect: $REDIRECT_MODE" >> "$SITE_CREDENTIALS" 2>/dev/null
            echo "-------------------" >> "$SITE_CREDENTIALS" 2>/dev/null
            ;;
        --php)
            echo "<?php phpinfo();" > "$WEB_ROOT/index.php"
            generate_nginx_config "$DOMAIN" "$WEB_ROOT" "$PHP_VERSION" "$REDIRECT_MODE" "$TYPE"
            init_credentials
            echo "Site: $ORIGINAL_DOMAIN" >> "$SITE_CREDENTIALS" 2>/dev/null
            echo "Type: PHP" >> "$SITE_CREDENTIALS" 2>/dev/null
            echo "Path: $WEB_ROOT" >> "$SITE_CREDENTIALS" 2>/dev/null
            echo "PHP Version: $PHP_VERSION" >> "$SITE_CREDENTIALS" 2>/dev/null
            echo "SSL: Disabled" >> "$SITE_CREDENTIALS" 2>/dev/null
            echo "Redirect: $REDIRECT_MODE" >> "$SITE_CREDENTIALS" 2>/dev/null
            echo "-------------------" >> "$SITE_CREDENTIALS" 2>/dev/null
            ;;
        --wp)
            wget -qO - https://wordpress.org/latest.tar.gz | tar xz -C "$WEB_ROOT" --strip-components=1
            chown -R www-data:www-data "$WEB_ROOT"
            mkdir -p "$WEB_ROOT/wp-content/uploads"
            chown -R www-data:www-data "$WEB_ROOT/wp-content/uploads"
            chmod -R 755 "$WEB_ROOT/wp-content/uploads"
            log_message "success" "Папка uploads настроена"
            WP_ADMIN_USER="admin_$(openssl rand -hex 4)"
            WP_ADMIN_PASS=$(openssl rand -base64 12)
            WP_ADMIN_EMAIL="admin@$ORIGINAL_DOMAIN"
            WP_SITE_TITLE="$ORIGINAL_DOMAIN"
            WP_PROTOCOL="http"
            WP_HOME="https://$DOMAIN"
            WP_SITEURL="http://$DOMAIN"
            DB_NAME=$(echo "$DOMAIN" | tr . _)
            DB_USER="wp_$DB_NAME"
            DB_PASS=$(openssl rand -base64 12)
            mysql -u root -p"$DB_ROOT_PASS" -e "CREATE DATABASE $DB_NAME;" 2>/dev/null
            mysql -u root -p"$DB_ROOT_PASS" -e "CREATE USER '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';" 2>/dev/null
            mysql -u root -p"$DB_ROOT_PASS" -e "GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost';" 2>/dev/null
            mysql -u root -p"$DB_ROOT_PASS" -e "FLUSH PRIVILEGES;" 2>/dev/null
            if mysql -u root -p"$DB_ROOT_PASS" -e "SHOW DATABASES LIKE '$DB_NAME';" | grep -q "$DB_NAME"; then
                log_message "success" "База данных $DB_NAME создана"
            else
                log_message "error" "База данных $DB_NAME не создана"
                cleanup_site "$DOMAIN"
                ERROR_COUNT=1
                log_message "info" "Создание сайта завершено" "end_operation" "Создание сайта завершено"
                exit 1
            fi
            cd "$WEB_ROOT"
            sudo -u www-data wp config create --dbname="$DB_NAME" --dbuser="$DB_USER" --dbpass="$DB_PASS" --dbhost=localhost --allow-root >/dev/null 2>&1
            if [ $? -eq 0 ]; then
                log_message "success" "wp-config.php создан"
            else
                log_message "error" "wp-config.php не создан"
                cleanup_site "$DOMAIN"
                ERROR_COUNT=1
                log_message "info" "Создание сайта завершено" "end_operation" "Создание сайта завершено"
                exit 1
            fi
            if [ -f "$WEB_ROOT/wp-config.php" ]; then
                log_message "success" "Файл wp-config.php готов"
            else
                log_message "error" "Файл wp-config.php отсутствует"
                cleanup_site "$DOMAIN"
                ERROR_COUNT=1
                log_message "info" "Создание сайта завершено" "end_operation" "Создание сайта завершено"
                exit 1
            fi
            sed -i "1a if (isset(\$_SERVER['HTTP_X_FORWARDED_PROTO']) && \$_SERVER['HTTP_X_FORWARDED_PROTO'] === 'https') { \$_SERVER['HTTPS'] = 'on'; }" "$WEB_ROOT/wp-config.php"
            sudo -u www-data wp config set WP_HOME "$WP_HOME" --allow-root >/dev/null 2>&1
            if [ $? -eq 0 ]; then
                log_message "success" "Константа WP_HOME установлена"
            else
                log_message "error" "Не удалось установить WP_HOME"
                cleanup_site "$DOMAIN"
                ERROR_COUNT=1
                log_message "info" "Создание сайта завершено" "end_operation" "Создание сайта завершено"
                exit 1
            fi
            sudo -u www-data wp config set WP_SITEURL "$WP_SITEURL" --allow-root >/dev/null 2>&1
            if [ $? -eq 0 ]; then
                log_message "success" "Константа WP_SITEURL установлена"
            else
                log_message "error" "Не удалось установить WP_SITEURL"
                cleanup_site "$DOMAIN"
                ERROR_COUNT=1
                log_message "info" "Создание сайта завершено" "end_operation" "Создание сайта завершено"
                exit 1
            fi
            sudo -u www-data wp core install --url="$WP_URL" --title="$WP_SITE_TITLE" --admin_user="$WP_ADMIN_USER" --admin_password="$WP_ADMIN_PASS" --admin_email="$WP_ADMIN_EMAIL" --allow-root >/dev/null 2>&1
            if [ $? -eq 0 ]; then
                log_message "success" "WordPress установлен"
            else
                log_message "error" "WordPress не установлен"
                cleanup_site "$DOMAIN"
                ERROR_COUNT=1
                log_message "info" "Создание сайта завершено" "end_operation" "Создание сайта завершено"
                exit 1
            fi
            if sudo -u www-data wp core is-installed --allow-root >/dev/null 2>&1; then
                log_message "success" "WordPress полностью готов"
            else
                log_message "error" "WordPress не установлен"
                cleanup_site "$DOMAIN"
                ERROR_COUNT=1
                log_message "info" "Создание сайта завершено" "end_operation" "Создание сайта завершено"
                exit 1
            fi
            sudo -u www-data wp option update home "$WP_HOME" --allow-root >/dev/null 2>&1
            if [ $? -eq 0 ]; then
                log_message "success" "Опция home обновлена"
            else
                log_message "error" "Не удалось обновить опцию home"
                cleanup_site "$DOMAIN"
                ERROR_COUNT=1
                log_message "info" "Создание сайта завершено" "end_operation" "Создание сайта завершено"
                exit 1
            fi
            sudo -u www-data wp option update siteurl "$WP_SITEURL" --allow-root >/dev/null 2>&1
            if [ $? -eq 0 ]; then
                log_message "success" "Опция siteurl обновлена"
            else
                log_message "error" "Не удалось обновить опцию siteurl"
                cleanup_site "$DOMAIN"
                ERROR_COUNT=1
                log_message "info" "Создание сайта завершено" "end_operation" "Создание сайта завершено"
                exit 1
            fi
            generate_nginx_config "$DOMAIN" "$WEB_ROOT" "$PHP_VERSION" "$REDIRECT_MODE" "$TYPE"
            init_credentials
            echo "Site: $ORIGINAL_DOMAIN" >> "$SITE_CREDENTIALS" 2>/dev/null
            echo "Type: WordPress" >> "$SITE_CREDENTIALS" 2>/dev/null
            echo "Path: $WEB_ROOT" >> "$SITE_CREDENTIALS" 2>/dev/null
            echo "PHP Version: $PHP_VERSION" >> "$SITE_CREDENTIALS" 2>/dev/null
            echo "SSL: Disabled" >> "$SITE_CREDENTIALS" 2>/dev/null
            echo "Redirect: $REDIRECT_MODE" >> "$SITE_CREDENTIALS" 2>/dev/null
            echo "WordPress Admin User: $WP_ADMIN_USER" >> "$SITE_CREDENTIALS" 2>/dev/null
            echo "WordPress Admin Password: $WP_ADMIN_PASS" >> "$SITE_CREDENTIALS" 2>/dev/null
            echo "WordPress Admin Email: $WP_ADMIN_EMAIL" >> "$SITE_CREDENTIALS" 2>/dev/null
            echo "WordPress DB Name: $DB_NAME" >> "$SITE_CREDENTIALS" 2>/dev/null
            echo "WordPress DB User: $DB_USER" >> "$SITE_CREDENTIALS" 2>/dev/null
            echo "WordPress DB Password: $DB_PASS" >> "$SITE_CREDENTIALS" 2>/dev/null
            echo "-------------------" >> "$SITE_CREDENTIALS" 2>/dev/null
            chmod 600 "$SITE_CREDENTIALS" 2>/dev/null
            log_message "success" "Домен успешно создан $ORIGINAL_DOMAIN"
            log_message "success" "WordPress админ: $WP_ADMIN_USER | $WP_ADMIN_PASS (Email: $WP_ADMIN_EMAIL)"
            log_message "success" "База данных: $DB_NAME, Пользователь: $DB_USER, Пароль: $DB_PASS"
            ;;
    esac

    if ! nginx -t >/dev/null 2>&1; then
        log_message "error" "Конфигурация Nginx невалидна"
        cleanup_site "$DOMAIN"
        ERROR_COUNT=1
        log_message "info" "Создание сайта завершено" "end_operation" "Создание сайта завершено"
        exit 1
    fi

    ln -sf "$CONFIG_FILE" "$ENABLED_FILE"
    if [ ! -L "$ENABLED_FILE" ]; then
        log_message "error" "Сайт $DOMAIN не активирован"
        cleanup_site "$DOMAIN"
        ERROR_COUNT=1
        log_message "info" "Создание сайта завершено" "end_operation" "Создание сайта завершено"
        exit 1
    fi

    systemctl restart nginx
    check_service nginx

    if [ -n "$SSL_TYPE" ]; then
        if setup_ssl "$DOMAIN" "$SSL_TYPE"; then
            log_message "success" "SSL ($SSL_TYPE) установлен для $ORIGINAL_DOMAIN"
            sed -i "/Site: $ORIGINAL_DOMAIN/,/-------------------/{/SSL: .*/s//SSL: Enabled ($SSL_TYPE)/}" "$SITE_CREDENTIALS" 2>/dev/null
        else
            log_message "warning" "Не удалось установить SSL ($SSL_TYPE) для $ORIGINAL_DOMAIN"
        fi
    fi

    if curl -I "http://$DOMAIN" >/dev/null 2>&1; then
        log_message "success" "Сайт $ORIGINAL_DOMAIN успешно создан и доступен"
    else
        log_message "warning" "Сайт $ORIGINAL_DOMAIN недоступен (проверьте DNS)"
    fi

    if [ "$TYPE" != "--wp" ]; then
        log_message "success" "Домен успешно создан $ORIGINAL_DOMAIN"
        log_message "success" "Сайт $ORIGINAL_DOMAIN успешно создан и доступен"
    fi

    SUCCESS_COUNT=1
    log_message "info" "Создание сайта завершено" "end_operation" "Создание сайта завершено"
}
