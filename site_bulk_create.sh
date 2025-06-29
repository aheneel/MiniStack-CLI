# site_bulk_create.sh - Команда для массового создания сайтов в MiniStack CLI
# Версия 1.0.31

bulk_create_sites() {
    clean_old_logs
    SKIP_AVAILABILITY_CHECK=0
    if [ "$1" = "--skip-availability-check" ]; then
        SKIP_AVAILABILITY_CHECK=1
        shift
    fi
    if [ $# -gt 0 ]; then
        log_message "error" "Неверные аргументы для --bulk: $@. Используйте без флагов или --skip-availability-check"
        exit 1
    fi
    log_message "info" "Запускаем массовый деплой сайтов..." "start_operation"
    echo -e "${YELLOW}Введите домены (по одному на строку, без http:// или /, например: domain.com). Для завершения введите 'done':${NC}"
    declare -a INPUT_DOMAINS
    while true; do
        read -r domain
        if [ "$domain" = "done" ]; then
            break
        fi
        if [ -z "$domain" ]; then
            continue
        fi
        INPUT_DOMAINS+=("$domain")
    done

    if [ ${#INPUT_DOMAINS[@]} -eq 0 ]; then
        log_message "error" "Не введено ни одного домена"
        exit 1
    fi

    declare -a VALID_DOMAINS
    declare -a ORIGINAL_DOMAINS
    for domain in "${INPUT_DOMAINS[@]}"; do
        cleaned_domain=$(clean_domain "$domain")
        if echo "$cleaned_domain" | grep -qE '^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'; then
            punycode_domain=$(convert_to_punycode "$cleaned_domain")
            VALID_DOMAINS+=("$punycode_domain")
            ORIGINAL_DOMAINS+=("$cleaned_domain")
        fi
    done

    if [ ${#VALID_DOMAINS[@]} -eq 0 ]; then
        log_message "error" "Нет валидных доменов для деплоя"
        exit 1
    fi

    while true; do
        echo -e "${YELLOW}Выберите версию PHP:${NC}"
        for i in "${!PHP_VERSIONS[@]}"; do
            echo -e "${YELLOW}$((i+1)).${NC} PHP ${PHP_VERSIONS[i]}"
        done
        echo -e "${YELLOW}Введите номер (1-${#PHP_VERSIONS[@]}):${NC}"
        read -r php_choice
        if [[ "$php_choice" =~ ^[1-5]$ ]]; then
            PHP_VERSION="${PHP_VERSIONS[$((php_choice-1))]}"
            PHP_FLAG="--php${PHP_VERSION//./}"
            log_message "info" "Выбрана версия PHP: $PHP_VERSION"
            break
        else
            log_message "error" "Неверный выбор PHP. Допустимые значения: 1-${#PHP_VERSIONS[@]}"
            exit 1
        fi
    done

    while true; do
        echo -e "${YELLOW}Выберите тип сайта:${NC}"
        echo -e "${YELLOW}1.${NC} HTML"
        echo -e "${YELLOW}2.${NC} PHP"
        echo -e "${YELLOW}3.${NC} WordPress"
        echo -e "${YELLOW}Введите номер (1-3):${NC}"
        read -r type_choice
        case $type_choice in
            1) SITE_TYPE="--html"; log_message "info" "Выбран тип сайта: $SITE_TYPE"; break ;;
            2) SITE_TYPE="--php"; log_message "info" "Выбран тип сайта: $SITE_TYPE"; break ;;
            3) SITE_TYPE="--wp"; log_message "info" "Выбран тип сайта: $SITE_TYPE"; break ;;
            *) log_message "error" "Неверный выбор типа сайта. Допустимые значения: 1-3"; exit 1 ;;
        esac
    done

    while true; do
        echo -e "${YELLOW}Выберите настройку редиректа:${NC}"
        echo -e "${YELLOW}1.${NC} Редирект на www"
        echo -e "${YELLOW}2.${NC} Редирект с www на домен"
        echo -e "${YELLOW}3.${NC} Без редиректа (оба варианта)"
        echo -e "${YELLOW}Введите номер (1-3):${NC}"
        read -r redirect_choice
        case $redirect_choice in
            1) REDIRECT_MODE="yes-www"; log_message "info" "Выбрана настройка редиректа: $REDIRECT_MODE"; break ;;
            2) REDIRECT_MODE="no-www"; log_message "info" "Выбрана настройка редиректа: $REDIRECT_MODE"; break ;;
            3) REDIRECT_MODE="none"; log_message "info" "Выбрана настройка редиректа: $REDIRECT_MODE"; break ;;
            *) log_message "error" "Неверный выбор редиректа. Допустимые значения: 1-3"; exit 1 ;;
        esac
    done

    while true; do
        echo -e "${YELLOW}Выпускать SSL-сертификаты для сайтов?${NC}"
        echo -e "${YELLOW}1.${NC} Let's Encrypt"
        echo -e "${YELLOW}2.${NC} Самоподписанный (OpenSSL)"
        echo -e "${YELLOW}3.${NC} Без SSL"
        echo -e "${YELLOW}Введите номер (1-3):${NC}"
        read -r ssl_choice
        case $ssl_choice in
            1) SSL_ENABLED="yes"; SSL_TYPE="--letsencrypt"; log_message "info" "Выпуск SSL: $SSL_TYPE"; break ;;
            2) SSL_ENABLED="yes"; SSL_TYPE="--selfsigned"; log_message "info" "Выпуск SSL: $SSL_TYPE"; break ;;
            3) SSL_ENABLED="no"; SSL_TYPE=""; log_message "info" "Выпуск SSL: отключен"; break ;;
            *) log_message "error" "Неверный выбор для SSL. Допустимые значения: 1-3"; exit 1 ;;
        esac
    done

    SUCCESS_COUNT=0
    ERROR_COUNT=0
    VALID_DOMAINS_COUNT=${#VALID_DOMAINS[@]}
    for i in "${!VALID_DOMAINS[@]}"; do
        domain="${VALID_DOMAINS[$i]}"
        original_domain="${ORIGINAL_DOMAINS[$i]}"
        log_message "info" "Обработка домена $original_domain (Punycode: $domain) [$((i+1))/$VALID_DOMAINS_COUNT]"
        if [ -f "/etc/nginx/sites-available/$domain" ] || [ -d "/var/www/$domain" ] || grep -q "Site: $original_domain" "$SITE_CREDENTIALS"; then
            log_message "error" "Сайт $original_domain уже существует"
            ((ERROR_COUNT++))
            continue
        fi
        if [ $SKIP_AVAILABILITY_CHECK -eq 0 ] && ! check_site_availability "$domain"; then
            ((ERROR_COUNT++))
            continue
        fi

        WEB_ROOT="/var/www/$domain/html"
        CONFIG_FILE="/etc/nginx/sites-available/$domain"
        ENABLED_FILE="/etc/nginx/sites-enabled/$domain"
        mkdir -p "$WEB_ROOT"
        chown -R www-data:www-data "$WEB_ROOT"
        chmod -R 755 "$WEB_ROOT"
        DB_ROOT_PASS=$(get_db_root_pass)

        case $SITE_TYPE in
            --html)
                echo "<h1>Welcome to $original_domain</h1>" > "$WEB_ROOT/index.html"
                echo "<?php phpinfo();" > "$WEB_ROOT/index.php"
                generate_nginx_config "$domain" "$WEB_ROOT" "$PHP_VERSION" "$REDIRECT_MODE" "$SITE_TYPE"
                init_credentials
                echo "Site: $original_domain" >> "$SITE_CREDENTIALS" 2>/dev/null
                echo "Type: HTML" >> "$SITE_CREDENTIALS" 2>/dev/null
                echo "Path: $WEB_ROOT" >> "$SITE_CREDENTIALS" 2>/dev/null
                echo "PHP Version: $PHP_VERSION" >> "$SITE_CREDENTIALS" 2>/dev/null
                echo "SSL: Disabled" >> "$SITE_CREDENTIALS" 2>/dev/null
                echo "Redirect: $REDIRECT_MODE" >> "$SITE_CREDENTIALS" 2>/dev/null
                echo "-------------------" >> "$SITE_CREDENTIALS" 2>/dev/null
                ;;
            --php)
                echo "<?php phpinfo();" > "$WEB_ROOT/index.php"
                generate_nginx_config "$domain" "$WEB_ROOT" "$PHP_VERSION" "$REDIRECT_MODE" "$SITE_TYPE"
                init_credentials
                echo "Site: $original_domain" >> "$SITE_CREDENTIALS" 2>/dev/null
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
                WP_ADMIN_EMAIL="admin@$original_domain"
                WP_SITE_TITLE="$original_domain"
                WP_PROTOCOL="http"
                WP_HOME="https://$domain"
                WP_SITEURL="http://$domain"
                DB_NAME=$(echo "$domain" | tr . _)
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
                    cleanup_site "$domain"
                    ((ERROR_COUNT++))
                    continue
                fi
                cd "$WEB_ROOT"
                sudo -u www-data wp config create --dbname="$DB_NAME" --dbuser="$DB_USER" --dbpass="$DB_PASS" --dbhost=localhost --allow-root >/dev/null 2>&1
                if [ $? -eq 0 ]; then
                    log_message "success" "wp-config.php создан"
                else
                    log_message "error" "wp-config.php не создан"
                    cleanup_site "$domain"
                    ((ERROR_COUNT++))
                    continue
                fi
                if [ -f "$WEB_ROOT/wp-config.php" ]; then
                    log_message "success" "Файл wp-config.php готов"
                else
                    log_message "error" "Файл wp-config.php отсутствует"
                    cleanup_site "$domain"
                    ((ERROR_COUNT++))
                    continue
                fi
                sed -i "1a if (isset(\$_SERVER['HTTP_X_FORWARDED_PROTO']) && \$_SERVER['HTTP_X_FORWARDED_PROTO'] === 'https') { \$_SERVER['HTTPS'] = 'on'; }" "$WEB_ROOT/wp-config.php"
                sudo -u www-data wp config set WP_HOME "$WP_HOME" --allow-root >/dev/null 2>&1
                if [ $? -eq 0 ]; then
                    log_message "success" "Константа WP_HOME установлена"
                else
                    log_message "error" "Не удалось установить WP_HOME"
                    cleanup_site "$domain"
                    ((ERROR_COUNT++))
                    continue
                fi
                sudo -u www-data wp config set WP_SITEURL "$WP_SITEURL" --allow-root >/dev/null 2>&1
                if [ $? -eq 0 ]; then
                    log_message "success" "Константа WP_SITEURL установлена"
                else
                    log_message "error" "Не удалось установить WP_SITEURL"
                    cleanup_site "$domain"
                    ((ERROR_COUNT++))
                    continue
                fi
                sudo -u www-data wp core install --url="$WP_URL" --title="$WP_SITE_TITLE" --admin_user="$WP_ADMIN_USER" --admin_password="$WP_ADMIN_PASS" --admin_email="$WP_ADMIN_EMAIL" --allow-root >/dev/null 2>&1
                if [ $? -eq 0 ]; then
                    log_message "success" "WordPress установлен"
                else
                    log_message "error" "WordPress не установлен"
                    cleanup_site "$domain"
                    ((ERROR_COUNT++))
                    continue
                fi
                if sudo -u www-data wp core is-installed --allow-root >/dev/null 2>&1; then
                    log_message "success" "WordPress полностью готов"
                else
                    log_message "error" "WordPress не установлен"
                    cleanup_site "$domain"
                    ((ERROR_COUNT++))
                    continue
                fi
                sudo -u www-data wp option update home "$WP_HOME" --allow-root >/dev/null 2>&1
                if [ $? -eq 0 ]; then
                    log_message "success" "Опция home обновлена"
                else
                    log_message "error" "Не удалось обновить опцию home"
                    cleanup_site "$domain"
                    ((ERROR_COUNT++))
                    continue
                fi
                sudo -u www-data wp option update siteurl "$WP_SITEURL" --allow-root >/dev/null 2>&1
                if [ $? -eq 0 ]; then
                    log_message "success" "Опция siteurl обновлена"
                else
                    log_message "error" "Не удалось обновить опцию siteurl"
                    cleanup_site "$domain"
                    ((ERROR_COUNT++))
                    continue
                fi
                generate_nginx_config "$domain" "$WEB_ROOT" "$PHP_VERSION" "$REDIRECT_MODE" "$SITE_TYPE"
                init_credentials
                echo "Site: $original_domain" >> "$SITE_CREDENTIALS" 2>/dev/null
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
                log_message "success" "Домен успешно создан $original_domain"
                log_message "success" "WordPress админ: $WP_ADMIN_USER | $WP_ADMIN_PASS (Email: $WP_ADMIN_EMAIL)"
                log_message "success" "База данных: $DB_NAME, Пользователь: $DB_USER, Пароль: $DB_PASS"
                ;;
        esac

        if ! nginx -t >/dev/null 2>&1; then
            log_message "error" "Конфигурация Nginx невалидна"
            cleanup_site "$domain"
            ((ERROR_COUNT++))
            continue
        fi

        ln -sf "$CONFIG_FILE" "$ENABLED_FILE"
        if [ ! -L "$ENABLED_FILE" ]; then
            log_message "error" "Сайт $domain не активирован"
            cleanup_site "$domain"
            ((ERROR_COUNT++))
            continue
        fi

        systemctl restart nginx
        check_service nginx

        if [ "$SSL_ENABLED" = "yes" ]; then
            if setup_ssl "$domain" "$SSL_TYPE"; then
                log_message "success" "SSL ($SSL_TYPE) установлен для $original_domain"
            else
                log_message "warning" "Не удалось установить SSL ($SSL_TYPE) для $original_domain"
            fi
        fi

        if curl -I "http://$domain" >/dev/null 2>&1; then
            log_message "success" "Сайт $original_domain успешно создан и доступен"
        else
            log_message "warning" "Сайт $original_domain недоступен (проверьте DNS)"
        fi

        if [ "$SITE_TYPE" != "--wp" ]; then
            log_message "success" "Домен успешно создан $original_domain"
            log_message "success" "Сайт $original_domain успешно создан и доступен"
        fi

        ((SUCCESS_COUNT++))
    done

    log_message "info" "Массовый деплой завершён" "end_operation" "Массовый деплой завершён"
}
