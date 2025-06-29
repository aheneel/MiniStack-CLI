# core.sh - Вспомогательные функции для MiniStack CLI
# Версия 1.0.31

# Централизованная функция логирования
log_message() {
    local type="$1"
    local msg="$2"
    local context="$3"  # start_operation, end_operation, или пусто
    local timestamp_screen=$(date '+%H:%M:%S')
    local timestamp_file=$(date '+%Y-%m-%d %H:%M:%S')
    local color
    local prefix

    case "$type" in
        "success")
            color="$GREEN"
            prefix="INFO"
            ;;
        "info")
            color="$BLUE"
            prefix="INFO"
            ;;
        "error")
            color="$RED"
            prefix="ERROR"
            ;;
        "warning")
            color="$YELLOW"
            prefix="WARNING"
            ;;
        *)
            color="$BLUE"
            prefix="INFO"
            ;;
    esac

    # Добавляем разделитель для начала операции
    if [ "$context" = "start_operation" ]; then
        echo -e "${BLUE}=== MiniStack ===${NC}"
        echo -e "[${timestamp_file}] === MiniStack ===" >> "$LOG_FILE"
    fi

    # Логируем сообщение
    echo -e "${color}${prefix} [$timestamp_screen] $msg${NC}"
    echo -e "[${timestamp_file}] ${prefix} - $msg" >> "$LOG_FILE"

    # Добавляем разделитель и мини-отчёт для конца операции
    if [ "$context" = "end_operation" ]; then
        echo -e "${BLUE}=== MiniStack ===${NC}"
        echo -e "[${timestamp_file}] === MiniStack ===" >> "$LOG_FILE"
        local success_count="${SUCCESS_COUNT:-0}"
        local error_count="${ERROR_COUNT:-0}"
        local operation_name="$4"
        echo -e "${BLUE}INFO - $operation_name: $success_count успехов, $error_count ошибок${NC}"
        echo -e "[${timestamp_file}] INFO - $operation_name: $success_count успехов, $error_count ошибок" >> "$LOG_FILE"
        if [ "$success_count" -gt 0 ]; then
            RANDOM_INDEX=$((RANDOM % ${#FUNNY_MESSAGES[@]}))
            RANDOM_MESSAGE="${FUNNY_MESSAGES[$RANDOM_INDEX]}"
            echo -e "${YELLOW}$RANDOM_MESSAGE${NC}"
            echo -e "[${timestamp_file}] INFO - $RANDOM_MESSAGE" >> "$LOG_FILE"
        fi
    fi
}

# Инициализация директорий и файлов для credentials и логов
init_credentials() {
    mkdir -p "$CREDENTIALS_DIR" /var/log
    touch "$SITE_CREDENTIALS" "$MARIADB_CREDENTIALS" "$LOG_FILE"
    chown root:root "$CREDENTIALS_DIR" "$SITE_CREDENTIALS" "$MARIADB_CREDENTIALS" "$LOG_FILE"
    chmod 700 "$CREDENTIALS_DIR"
    chmod 600 "$SITE_CREDENTIALS" "$MARIADB_CREDENTIALS" "$LOG_FILE"
    log_message "info" "Директории и файлы credentials инициализированы"
}

# Очистка временных файлов и базы данных для домена при ошибке
cleanup_site() {
    local domain="$1"
    log_message "info" "Очищены временные файлы и база для $domain"
    WEB_ROOT="/var/www/$domain"
    CONFIG_FILE="/etc/nginx/sites-available/$domain"
    ENABLED_FILE="/etc/nginx/sites-enabled/$domain"
    DB_NAME=$(echo "$domain" | tr . _)
    DB_ROOT_PASS=$(get_db_root_pass)
    [ -f "$ENABLED_FILE" ] && rm -f "$ENABLED_FILE"
    [ -f "$CONFIG_FILE" ] && rm -f "$CONFIG_FILE"
    [ -d "$WEB_ROOT" ] && rm -rf "$WEB_ROOT"
    mysql -u root -p"$DB_ROOT_PASS" -e "DROP DATABASE IF EXISTS $DB_NAME;" 2>/dev/null
    mysql -u root -p"$DB_ROOT_PASS" -e "DROP USER IF EXISTS 'wp_$DB_NAME'@'localhost';" 2>/dev/null
    if grep -q "Site: $domain" "$SITE_CREDENTIALS"; then
        sed -i "/Site: $domain/,/-------------------/d" "$SITE_CREDENTIALS" 2>/dev/null
    fi
}

# Удаление логов старше 30 дней
clean_old_logs() {
    if [ -f "$LOG_FILE" ]; then
        if find "$LOG_FILE" -mtime +30 -exec rm -f {} \; 2>/dev/null; then
            if [ ! -f "$LOG_FILE" ]; then
                log_message "info" "Лог старше 30 дней удалён, создан новый"
                touch "$LOG_FILE"
                chmod 600 "$LOG_FILE"
            fi
        fi
    fi
}

# Преобразование домена в Punycode
convert_to_punycode() {
    local domain="$1"
    if command -v idn2 >/dev/null 2>&1; then
        punycode_domain=$(idn2 "$domain" 2>/dev/null)
        if [ $? -eq 0 ] && [ -n "$punycode_domain" ]; then
            echo "$punycode_domain"
        else
            echo "$domain"
        fi
    else
        log_message "warning" "Утилита idn2 не установлена, домен $domain использован без преобразования"
        echo "$domain"
    fi
}

clean_domain() {
    local domain=$1
    domain=$(echo "$domain" | sed -E 's|^https?://||; s|://||; s|/+$||')
    echo "$domain"
}

get_db_root_pass() {
    if [ -f "$MARIADB_CREDENTIALS" ]; then
        DB_ROOT_PASS=$(grep "MariaDB Root Password" "$MARIADB_CREDENTIALS" | cut -d' ' -f4)
        if [ -z "$DB_ROOT_PASS" ]; then
            log_message "error" "Пароль root MariaDB не найден в $MARIADB_CREDENTIALS"
            exit 1
        fi
    else
        log_message "error" "Файл $MARIADB_CREDENTIALS не существует"
        exit 1
    fi
    echo "$DB_ROOT_PASS"
}

check_site_exists() {
    local domain=$1
    if [ -f "/etc/nginx/sites-available/$domain" ] || [ -d "/var/www/$domain" ] || grep -q "Site: $domain" "$SITE_CREDENTIALS"; then
        log_message "error" "Сайт $domain уже существует"
        return 1
    fi
    return 0
}

check_site_not_exists() {
    local domain=$1
    if [ ! -f "/etc/nginx/sites-available/$domain" ] && [ ! -d "/var/www/$domain" ] && ! grep -q "Site: $domain" "$SITE_CREDENTIALS"; then
        log_message "error" "Домен $domain уже удалён"
        return 1
    fi
    return 0
}

check_site_availability() {
    local domain=$1
    if curl -s https://$domain | grep -q "MiniStack CLI"; then
        log_message "info" "Сайт $domain доступен по HTTPS"
        return 0
    elif curl -s http://$domain | grep -q "MiniStack CLI"; then
        log_message "info" "Сайт $domain доступен по HTTP"
        return 0
    else
        log_message "error" "Сайт $domain недоступен ни по HTTPS, ни по HTTP"
        return 1
    fi
}

check_package() {
    local package=$1
    if dpkg -l "$package" >/dev/null 2>&1; then
        log_message "success" "Пакет $package установлен"
        return 0
    else
        log_message "error" "Пакет $package не установлен"
        exit 1
    fi
}

check_service() {
    local service=$1
    if systemctl is-active "$service" >/dev/null; then
        log_message "success" "Служба $service активна"
        return 0
    else
        log_message "error" "Служба $service не активна"
        exit 1
    fi
}

check_php() {
    local version=$1
    if php${version} --version >/dev/null 2>&1; then
        log_message "success" "PHP $version установлен"
        return 0
    else
        log_message "error" "PHP $version не установлен"
        exit 1
    fi
}

check_wp_cli() {
    if wp --version --allow-root >/dev/null 2>&1; then
        log_message "success" "wp-cli установлен"
        return 0
    else
        log_message "error" "wp-cli не установлен"
        exit 1
    fi
}
