# nginx_utils.sh - Функции для генерации Nginx-конфигов
# Версия 1.0.31

generate_nginx_config() {
    local domain="$1"
    local web_root="$2"
    local php_version="$3"
    local redirect_mode="$4"
    local site_type="$5"
    local config_file="/etc/nginx/sites-available/$domain"

    if [ "$redirect_mode" = "yes-www" ]; then
        cat > "$config_file" <<EOL
server {
    listen 80;
    server_name $domain;
    return 301 http://www.$domain\$request_uri;
}
server {
    listen 80;
    server_name www.$domain;
    root $web_root;
    index index.php index.html index.htm;
    client_max_body_size 256M;
    client_body_timeout 300s;
    client_header_timeout 300s;
    include /etc/nginx/common/security_headers.conf;
    location / {
        try_files \$uri \$uri/ $( [ "$site_type" = "--wp" ] || [ "$site_type" = "--php" ] && echo "/index.php?\$args" || echo "=404" );
    }
    location ~ \.php$ {
        include fastcgi_params;
        fastcgi_pass unix:/run/php/php${php_version}-fpm.sock;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
    }
}
EOL
    elif [ "$redirect_mode" = "no-www" ]; then
        cat > "$config_file" <<EOL
server {
    listen 80;
    server_name www.$domain;
    return 301 http://$domain\$request_uri;
}
server {
    listen 80;
    server_name $domain;
    root $web_root;
    index index.php index.html index.htm;
    client_max_body_size 256M;
    client_body_timeout 300s;
    client_header_timeout 300s;
    include /etc/nginx/common/security_headers.conf;
    location / {
        try_files \$uri \$uri/ $( [ "$site_type" = "--wp" ] || [ "$site_type" = "--php" ] && echo "/index.php?\$args" || echo "=404" );
    }
    location ~ \.php$ {
        include fastcgi_params;
        fastcgi_pass unix:/run/php/php${php_version}-fpm.sock;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
    }
}
EOL
    else
        cat > "$config_file" <<EOL
server {
    listen 80;
    server_name $domain www.$domain;
    root $web_root;
    index index.php index.html index.htm;
    client_max_body_size 256M;
    client_body_timeout 300s;
    client_header_timeout 300s;
    include /etc/nginx/common/security_headers.conf;
    location / {
        try_files \$uri \$uri/ $( [ "$site_type" = "--wp" ] || [ "$site_type" = "--php" ] && echo "/index.php?\$args" || echo "=404" );
    }
    location ~ \.php$ {
        include fastcgi_params;
        fastcgi_pass unix:/run/php/php${php_version}-fpm.sock;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
    }
}
EOL
    fi
}