# utils.sh - Утилитарные функции для MiniStack CLI
# Версия 1.0.31

welcome() {
    clean_old_logs
    log_message "info" "MiniStack CLI v$VERSION"
    log_message "info" "Управление LEMP-стеком (Nginx, PHP, MariaDB)"
    log_message "info" "Для справки: sudo ms help"
}

show_help() {
    clean_old_logs
    log_message "info" "MiniStack CLI v$VERSION - Справка" "start_operation"
    log_message "info" "Использование: sudo ms <команда> [аргументы]"
    log_message "info" "Команды:"
    log_message "info" "1. sudo ms stack install - Установить LEMP-стек"
    log_message "info" "2. sudo ms site create <domain> [--html|--php|--wp] [--php74|--php80|--php81|--php82|--php83] [--yes-www|--no-www] - Создать сайт"
    log_message "info" "3. sudo ms site bulk - Массовый деплой сайтов"
    log_message "info" "4. sudo ms site bulk-delete - Массовое удаление сайтов"
    log_message "info" "5. sudo ms site delete <domain> - Удалить сайт"
    log_message "info" "6. sudo ms site info <domain> - Показать информацию о сайте"
    log_message "info" "7. sudo ms secure --ssl <domain> [--letsencrypt|--selfsigned] - Настроить SSL (по умолчанию --letsencrypt)"
    log_message "info" "8. sudo ms clean - Удалить лишние HTTP-заголовки"
    log_message "info" "9. sudo ms info - Показать статус сервисов"
    log_message "info" "10. sudo ms help - Показать справку"
    log_message "info" "Логи: $LOG_FILE"
    log_message "info" "Учетные данные: $CREDENTIALS_DIR"
    log_message "info" "Справка завершена" "end_operation" "Справка завершена"
}

setup_php_repository() {
    log_message "info" "Настраиваем репозиторий PHP..."
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        if [[ "$ID" == "debian" && "$VERSION_ID" == "11" ]]; then
            apt install -y apt-transport-https lsb-release ca-certificates curl
            wget -O /etc/apt/trusted.gpg.d/php.gpg https://packages.sury.org/php/apt.gpg
            echo "deb https://packages.sury.org/php/ $(lsb_release -sc) main" > /etc/apt/sources.list.d/php.list
        elif [[ "$ID" == "ubuntu" ]]; then
            apt install -y software-properties-common
            add-apt-repository ppa:ondrej/php -y
        else
            log_message "error" "Неподдерживаемый дистрибутив ($ID $VERSION_ID)"
            exit 1
        fi
    else
        log_message "error" "Не удалось определить дистрибутив"
        exit 1
    fi
    apt update
    log_message "success" "Репозиторий PHP настроен!"
}

final_check_and_restart() {
    clean_old_logs
    log_message "info" "Проверяем компоненты..." "start_operation"
    check_package nginx
    check_package mariadb-server
    check_package certbot
    check_package libidn2-0
    check_wp_cli
    check_service nginx
    check_service mariadb
    for version in "${PHP_VERSIONS[@]}"; do
        check_service php${version}-fpm
    done
    if [ -f /etc/nginx/sites-available/default ]; then
        log_message "success" "Дефолтный конфиг Nginx на месте"
    else
        log_message "error" "Дефолтный конфиг Nginx отсутствует"
        exit 1
    fi
    if [ -f /etc/ssl/certs/nginx-selfsigned.crt ] && [ -f /etc/ssl/private/nginx-selfsigned.key ]; then
        log_message "success" "Самоподписанный SSL-сертификат готов"
    else
        log_message "error" "Самоподписанный SSL-сертификат отсутствует"
        exit 1
    fi
    if curl -s http://localhost | grep -q "MiniStack CLI"; then
        log_message "success" "Дефолтный сайт доступен и содержит MiniStack CLI"
    else
        log_message "error" "Дефолтный сайт недоступен или не содержит MiniStack CLI"
        exit 1
    fi
    log_message "info" "Перезапускаем сервисы..."
    systemctl restart nginx
    check_service nginx
    systemctl restart mariadb
    check_service mariadb
    for version in "${PHP_VERSIONS[@]}"; do
        systemctl restart php${version}-fpm
        check_service php${version}-fpm
    done
    log_message "success" "Все сервисы перезапущены!"
    SUCCESS_COUNT=1
    ERROR_COUNT=0
    log_message "info" "Проверка компонентов завершена" "end_operation" "Проверка компонентов завершена"
}