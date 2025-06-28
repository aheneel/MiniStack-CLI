# stack_install.sh - Команда для установки LEMP-стека в MiniStack CLI
# Версия 1.0.31

install_stack() {
    . /usr/local/lib/minStack/utils.sh
    clean_old_logs
    if [ $# -gt 0 ]; then
        log_message "error" "Неверные аргументы для --install: $@. Используйте без флагов"
        exit 1
    fi
    welcome
    log_message "info" "Проверяем установку LEMP-стека..." "start_operation"
    init_credentials
    if check_stack_installed; then
        SUCCESS_COUNT=1
        ERROR_COUNT=0
        log_message "info" "LEMP-стек уже установлен" "end_operation" "Установка стека завершена"
        exit 0
    fi
    log_message "info" "Запускаем установку LEMP-стека..."
    export DEBIAN_FRONTEND=noninteractive
    apt update && apt upgrade -y
    log_message "success" "Система обновлена!"
    setup_php_repository
    apt install -y nginx libidn2-0 idn2
    check_package nginx
    check_package libidn2-0
    systemctl enable nginx
    systemctl start nginx
    check_service nginx
    mkdir -p /etc/ssl/private /etc/ssl/certs
    openssl req -x509 -nodes -days 3650 -newkey rsa:2048 -keyout /etc/ssl/private/nginx-selfsigned.key -out /etc/ssl/certs/nginx-selfsigned.crt -subj "/CN=localhost" || { log_message "error" "Не удалось создать самоподписанный сертификат"; exit 1; }
    chmod 600 /etc/ssl/private/nginx-selfsigned.key
    log_message "success" "Самоподписанный SSL-сертификат создан!"
    mkdir -p /var/www/html
    chown www-data:www-data /var/www/html
    chmod 755 /var/www/html
    echo "MiniStack CLI" > /var/www/html/index.html
    chmod 644 /var/www/html/index.html
    log_message "success" "Дефолтный index.html создан!"
    cat > /etc/nginx/sites-available/default <<EOL
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;
    root /var/www/html;
    index index.html;
}
server {
    listen 443 ssl default_server;
    listen [::]:443 ssl default_server;
    server_name _;
    ssl_certificate /etc/ssl/certs/nginx-selfsigned.crt;
    ssl_certificate_key /etc/ssl/private/nginx-selfsigned.key;
    root /var/www/html;
    index index.html;
}
EOL
    nginx -t && systemctl reload nginx
    log_message "success" "Дефолтный конфиг Nginx настроен!"
    DB_ROOT_PASS=$(openssl rand -base64 12)
    apt install -y mariadb-server mariadb-client
    check_package mariadb-server
    systemctl enable mariadb
    systemctl start mariadb
    check_service mariadb
    mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '$DB_ROOT_PASS';" 2>/dev/null
    mysql -e "DELETE FROM mysql.user WHERE User='';" 2>/dev/null
    mysql -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');" 2>/dev/null
    mysql -e "DROP DATABASE IF EXISTS test;" 2>/dev/null
    mysql -e "FLUSH PRIVILEGES;" 2>/dev/null
    log_message "success" "MariaDB настроена!"
    echo "MariaDB Root Password: $DB_ROOT_PASS" > "$MARIADB_CREDENTIALS"
    chmod 600 "$MARIADB_CREDENTIALS"
    for version in "${PHP_VERSIONS[@]}"; do
        apt install -y php${version} php${version}-fpm php${version}-mysql php${version}-mbstring php${version}-xml php${version}-curl php${version}-zip
        check_php "$version"
        PHP_INI="/etc/php/${version}/fpm/php.ini"
        if [ -f "$PHP_INI" ]; then
            sed -i 's/upload_max_filesize = .*/upload_max_filesize = 256M/' "$PHP_INI"
            sed -i 's/post_max_size = .*/post_max_size = 256M/' "$PHP_INI"
            sed -i 's/memory_limit = .*/memory_limit = 512M/' "$PHP_INI"
            sed -i 's/max_execution_time = .*/max_execution_time = 300/' "$PHP_INI"
            sed -i 's/max_input_time = .*/max_input_time = 300/' "$PHP_INI"
            sed -i 's/expose_php = On/expose_php = Off/' "$PHP_INI"
            log_message "success" "Конфигурация PHP $version обновлена"
        else
            log_message "error" "Файл php.ini для PHP $version не найден"
            exit 1
        fi
        systemctl enable php${version}-fpm
        systemctl start php${version}-fpm
        check_service php${version}-fpm
    done
    log_message "success" "PHP настроен!"
    apt install -y certbot python3-certbot-nginx
    check_package certbot
    wget -qO /usr/local/bin/wp https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
    chmod +x /usr/local/bin/wp
    check_wp_cli
    mkdir -p /etc/nginx/common
    cat > /etc/nginx/common/security_headers.conf <<EOL
add_header X-Content-Type-Options "nosniff" always;
add_header X-Frame-Options "DENY" always;
add_header X-XSS-Protection "1; mode=block" always;
add_header Referrer-Policy "strict-origin-when-cross-origin" always;
add_header Permissions-Policy "geolocation=(), camera=(), microphone=()" always;
add_header Content-Security-Policy "default-src 'self' https: data: blob:; img-src 'self' https: data: blob:; script-src 'self' https: 'unsafe-inline' 'unsafe-eval' blob:; style-src 'self' https: 'unsafe-inline'; font-src 'self' https: data:; connect-src 'self' https: wss:; frame-src https: *.youtube.com *.vimeo.com blob:;" always;
EOL
    log_message "success" "Безопасные заголовки настроены!"
    clean_headers
    final_check_and_restart
    log_message "success" "LEMP-стек установлен!"
    SUCCESS_COUNT=1
    ERROR_COUNT=0
    log_message "info" "Установка стека завершена" "end_operation" "Установка стека завершена"
}
