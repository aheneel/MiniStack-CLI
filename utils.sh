# utils.sh - Утилитарные функции для MiniStack CLI
# Версия 1.0.31

welcome() {
    clean_old_logs
    log_message "info" "MiniStack CLI v$VERSION"
    log_message "info" "Управление LEMP-стеком (Nginx, PHP, MariaDB)"
    log_message "info" "Для справки: sudo ms --help"
}

show_help() {
    clean_old_logs
    BOLD='\033[1m'
    echo -e "${BLUE}=== MiniStack CLI v$VERSION ===${NC}"
    echo -e "${YELLOW}Использование:${NC} sudo ms <команда> [аргументы]\n"
    echo -e "${GREEN}Команды:${NC}"
    echo -e "  ${BOLD}${YELLOW}sudo ms stack --install${NC}          Установить LEMP-стек (Nginx, PHP, MariaDB)"
    echo -e "  ${BOLD}${YELLOW}sudo ms site --create <domain> [--html|--php|--wp] [--php74|--php80|--php81|--php82|--php83] [--yes-www|--no-www] [--ssl-lets|--ssl-open]${NC}"
    echo -e "                                   Создать сайт (дефолт: PHP 7.4, без редиректа, без SSL)"
    echo -e "  ${BOLD}${YELLOW}sudo ms site --bulk${NC}              Массовый деплой сайтов (интерактивный ввод)"
    echo -e "  ${BOLD}${YELLOW}sudo ms site --bulk-delete${NC}       Массовое удаление сайтов (интерактивный ввод)"
    echo -e "  ${BOLD}${YELLOW}sudo ms site --delete <domain>${NC}   Удалить сайт"
    echo -e "  ${BOLD}${YELLOW}sudo ms site --info <domain>${NC}     Показать информацию о сайте"
    echo -e "  ${BOLD}${YELLOW}sudo ms secure --ssl <domain> [--letsencrypt|--selfsigned]${NC}"
    echo -e "                                   Настроить SSL (по умолчанию --letsencrypt)"
    echo -e "  ${BOLD}${YELLOW}sudo ms --clean${NC}                  Удалить лишние HTTP-заголовки"
    echo -e "  ${BOLD}${YELLOW}sudo ms --info${NC}                   Показать статус сервисов"
    echo -e "  ${BOLD}${YELLOW}sudo ms --help${NC}                   Показать эту справку"
    echo -e "\n${GREEN}Дополнительно:${NC}"
    echo -e "  ${YELLOW}Логи:${NC} $LOG_FILE"
    echo -e "  ${YELLOW}Учетные данные:${NC} $CREDENTIALS_DIR"
    echo -e "${BLUE}=======================${NC}"
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

check_stack_installed() {
    local all_installed=1
    log_message "info" "Проверяем, установлен ли LEMP-стек..."
    if ! dpkg -l nginx >/dev/null 2>&1; then
        log_message "error" "Nginx не установлен"
        all_installed=0
    fi
    if ! dpkg -l mariadb-server >/dev/null 2>&1; then
        log_message "error" "MariaDB не установлен"
        all_installed=0
    fi
    if ! dpkg -l certbot >/dev/null 2>&1; then
        log_message "error" "Certbot не установлен"
        all_installed=0
    fi
    if ! dpkg -l libidn2-0 >/dev/null 2>&1; then
        log_message "error" "libidn2-0 не установлен"
        all_installed=0
    fi
    if ! wp --version --allow-root >/dev/null 2>&1; then
        log_message "error" "wp-cli не установлен"
        all_installed=0
    fi
    for version in "${PHP_VERSIONS[@]}"; do
        if ! php${version} --version >/dev/null 2>&1; then
            log_message "error" "PHP $version не установлен"
            all_installed=0
        fi
    done
    if [ ! -f /etc/nginx/sites-available/default ]; then
        log_message "error" "Дефолтный конфиг Nginx отсутствует"
        all_installed=0
    fi
    if [ ! -f /etc/ssl/certs/nginx-selfsigned.crt ] || [ ! -f /etc/ssl/private/nginx-selfsigned.key ]; then
        log_message "error" "Самоподписанный SSL-сертификат отсутствует"
        all_installed=0
    fi
    if [ "$all_installed" -eq 1 ]; then
        log_message "info" "LEMP-стек уже установлен"
        return 0
    else
        return 1
    fi
}
