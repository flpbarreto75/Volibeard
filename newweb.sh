#!/bin/bash

echo "Please provide the port Number : "

read PORT

echo "Please provide the Service name : "

read SERVICE

# check for usage of the port in the host and sevice name by docker .

checker () {

        PORT=$1

        SERVICE=$2

        # check for port usage

        HOST_PORT=$(lsof -i -P -n | grep *:$PORT | awk '{print $10}')

        if [[ $HOST_PORT == "(LISTEN)" ]]
        then
                echo "port $PORT already being used, please use another."
                echo "Enter a new port : "
                read PORT

                checker $PORT $SERVICE
        else
                echo "$PORT is good "
        fi

        # check for the service name to be use in docker

        SERVICE_C=$(docker ps --format '{{.Names}}' | grep $SERVICE )

        echo $SERVICE_C

        if [[ $SERVICE == $SERVICE_C ]]
        then
                DOCKER_ID=$(docker ps | grep $SERVICE | awk '{print $1 }')
                echo "Service alsready being used by docker ID : $DOCKER_ID "
                echo "Please User another name : "
                read SERVICE

                checker $PORT $SERVICE
        else
                echo "Service name ($SERVICE) is good "
        fi
}

#make a call for the checker function
checker $PORT $SERVICE


# once it is confirmed that the port and service name is good it creates the home dirretory for the web service
mkdir /data/Web/$SERVICE

# it copy the default configs from the docker image into the home directory
docker create --name nginxcopy trafex/alpine-nginx-php7
docker cp nginxcopy:/var/www/html/ /data/Web/$SERVICE/www
docker cp nginxcopy:/etc/php7/ /data/Web/$SERVICE/php_config
docker cp nginxcopy:/var/log/nginx   /data/Web/$SERVICE/logs
docker rm nginxcopy


# initiates the docker container using the arguments given
docker run -d \
    --name $SERVICE \
    --restart unless-stopped \
    --network web_services \
    -p $PORT:8080 \
    --link mysql:db \
    -v /data/Web/$SERVICE/www:/var/www/html \
    -v /data/Web/$SERVICE/php_config:/etc/php7/ \
    -v /data/Web/$SERVICE/logs:/var/log/nginx \
    trafex/alpine-nginx-php7

# changed the ownership for the folders inside the home directory to nobody with no group
chown -R nobody: /data/Web/$SERVICE/*

# creates the logs direcetory for the reverse proxy
mkdir /var/log/nginx/$SERVICE


certbot certonly  --nginx -d $SERVICE.volibeard.com


# creates the  Nginx reverse proxy config
echo "

server {
    server_name  $SERVICE.volibeard.com;

    access_log  /var/log/nginx/$SERVICE/access.log;
    error_log   /var/log/nginx/$SERVICE/error.log;

    location / {


       proxy_set_header        Host \$host;
       proxy_set_header        X-Real-IP \$remote_addr;
       proxy_set_header        X-Forwarded-For \$proxy_add_x_forwarded_for;
       proxy_set_header        X-Forwarded-Proto \$scheme;
       proxy_pass              http://127.0.0.1:$PORT;
       proxy_read_timeout      90;
       proxy_redirect          http://127.0.0.1:$PORT  http://$SERVICE.volibeard.com;
    }


    listen 443 ssl; # managed by Certbot
    ssl_certificate /etc/letsencrypt/live/$SERVICE.volibeard.com/fullchain.pem; # managed by Certbot
    ssl_certificate_key /etc/letsencrypt/live/$SERVICE.volibeard.com/privkey.pem; # managed by Certbot
    include /etc/letsencrypt/options-ssl-nginx.conf; # managed by Certbot
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem; # managed by Certbot


}


server {

    if (\$host = $SERVICE.volibeard.com) {
            return 301 https://\$host\$request_uri;
    } # managed by Certbot


    listen 80;
    server_name  $SERVICE.volibeard.com;
    return 404; # managed by Certbot


}


" | tee > /etc/nginx/sites-available/$SERVICE


# cretes a softlink of the nginx config to sites enabled
ln -s /etc/nginx/sites-available/$SERVICE /etc/nginx/sites-enabled/


#restart NGINX
nginx -s reload





#echo the confirmatin of the service created based on the arguments provided
echo "Nginx server was creted for : $SERVICE"
echo "You can connect to the mysql via host : db "
echo "you can access your site via $SERVICE.volibeard.com"



