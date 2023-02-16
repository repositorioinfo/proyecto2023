#!/bin/bash

HOST=${1:-'dominio'}
#parametros opcionales
PROYECT=${2:-'https://gitlab.com/inpulsa/facturador/pro5.git'}
REMOTE='git@gitlab.com:'$(echo $PROYECT | sed -e s#^https://gitlab.com/##)
SERVICE_NUMBER=${3:-'1'}
PATH_INSTALL=$(echo $HOME)
DIR=$(echo $PROYECT | rev | cut -d'/' -f1 | rev | cut -d '.' -f1)$SERVICE_NUMBER
MYSQL_PORT_HOST=${4:-'3306'}
MYSQL_USER=${5:-'root'}
MYSQL_PASSWORD=${6:-$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 20 ; echo '')}
MYSQL_DATABASE=${7:-$DIR}
ADMIN_PASSWORD=${8:-$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 10 ; echo '')}
EMAIL=${9:-'izyfac@gmail.com'}

if [ "$HOST" = "dominio" ]; then
    echo no ha ingresado dominio, vuelva a ejecutar el script agregando un dominio como primer parametro
    exit 1
fi

echo "Actualizando sistema"
apt-get -y update
apt-get -y upgrade

echo "Instalando dependencias"
apt-get -y install git-core zip unzip git curl
apt-get -y install software-properties-common
apt-get -y install python-software-properties
apt-get -y install libtesseract-dev libleptonica-dev liblept5
apt-get -y install tesseract-ocr

echo "Instalando letsencrypt"
apt-get -y install letsencrypt
mkdir $HOME/certs/
#mkdir $DIR/certs/

echo "Instalando servidor web"
add-apt-repository ppa:ondrej/php -y
apt-get -y update
apt-get -y install php7.4 php7.4-mbstring php7.4-soap php7.4-zip php7.4-mysql php7.4-curl php7.4-gd php7.4-xml

echo "Instalando mysql"
apt-get -y install mysql-server-5.7 mysql-client-5.7

mysql -uroot <<MYSQL_SCRIPT
CREATE DATABASE $MYSQL_DATABASE;
ALTER USER '$MYSQL_USER'@'localhost' IDENTIFIED WITH mysql_native_password BY '$MYSQL_PASSWORD';
FLUSH PRIVILEGES;
MYSQL_SCRIPT

echo "Instalando composer"
apt-get -y install composer

cd /var/www/html/

echo "Clonando repositorio"

git clone "$PROYECT" "$DIR"

cp $DIR/.env.example $DIR/.env

echo "Configurando env"
cd "$DIR"

sed -i "/DB_DATABASE=/c\DB_DATABASE=$MYSQL_DATABASE" .env
sed -i "/DB_PASSWORD=/c\DB_PASSWORD=$MYSQL_PASSWORD" .env
sed -i "/DB_USERNAME=/c\DB_USERNAME=$MYSQL_USER" .env
sed -i "/APP_URL_BASE=/c\APP_URL_BASE=$HOST" .env
sed -i '/APP_URL=/c\APP_URL=http://${APP_URL_BASE}' .env
sed -i '/FORCE_HTTPS=/c\FORCE_HTTPS=false' .env
sed -i '/APP_DEBUG=/c\APP_DEBUG=false' .env
sed -i '/PREFIX_DATABASE=/c\PREFIX_DATABASE=empresa' .env

echo "Configurando archivo para usuario administrador"
mv "database/seeds/DatabaseSeeder.php" "database/seeds/DatabaseSeeder.php.bk"
cat << EOF > database/seeds/DatabaseSeeder.php
<?php

use Illuminate\Database\Seeder;
use Illuminate\Support\Facades\DB;

class DatabaseSeeder extends Seeder
{
    /**
     * Seed the application's database.
     *
     * @return void
     */
    public function run()
    {
        App\Models\System\User::create([
            'name' => 'SuperAdmin',
            'email' => 'admin@$HOST',
            'password' => bcrypt('$ADMIN_PASSWORD'),
        ]);
 

        DB::table('plan_documents')->insert([
            ['id' => 1, 'description' => 'Facturas, boletas, notas de débito y crédito, resúmenes y anulaciones' ],
            ['id' => 2, 'description' => 'Guias de remisión' ],
            ['id' => 3, 'description' => 'Retenciones'],
            ['id' => 4, 'description' => 'Percepciones']
        ]);

        App\Models\System\Plan::create([
            'name' => 'Ilimitado',
            'pricing' =>  99,
            'limit_users' => 0,
            'limit_documents' =>  0,
            'plan_documents' => [1,2,3,4],
            'locked' => true
        ]);

    }
}

EOF

echo "Configurando proyecto"

composer install
php artisan migrate:refresh --seed
php artisan key:generate
php artisan storage:link
php artisan config:cache
php artisan cache:clear

rm database/seeds/DatabaseSeeder.php
mv database/seeds/DatabaseSeeder.php.bk database/seeds/DatabaseSeeder.php

echo "Configurando permisos"
chmod -R 777 "storage/" "bootstrap/cache" "vendor/mpdf/mpdf"
chmod +x script-update.sh

echo "Configurando $HOST"
cd /etc/apache2/sites-available/

cat << EOF > $HOST.conf
<VirtualHost *:80>   
     ServerAdmin admin@$HOST
     DocumentRoot /var/www/html/$DIR/public
     ServerName $HOST
     ServerAlias *.$HOST

     <Directory /var/www/html/$DIR/public>
        Options +FollowSymlinks
        AllowOverride All
        Require all granted
     </Directory>

     ErrorLog ${APACHE_LOG_DIR}/error.log
     CustomLog ${APACHE_LOG_DIR}/access.log combined
</VirtualHost>

EOF

a2dissite 000-default.conf
a2ensite $HOST.conf
a2enmod rewrite
service apache2 restart

#Configurar clave ssh
read -p "configurar clave SSH para actualización automática? (requiere acceso a https://gitlab.com/profile/keys). si[s] no[n] " ssh
if [ "$ssh" = "s" ]; then
    mkdir /var/www/html/$DIR/ssh/
    #mkdir /var/www/html/.ssh/
    mkdir /var/www/.ssh/
    echo "generando clave SSH"
    ssh-keygen -t rsa -q -P "" -f /var/www/html/$DIR/ssh/id_rsa
    echo "cambiando remote"
    cd /var/www/html/$DIR/
    git remote set-url origin $REMOTE

    ssh-keyscan -H gitlab.com >> /var/www/html/$DIR/ssh/known_hosts

    chown -R www-data ssh/
    #chown -R www-data /var/www/html/.ssh
    #chown -R www-data /var/www/html
    chown -R www-data /var/www/.ssh/
fi

echo "Finalizado el despliegue"

echo "Ruta del proyecto dentro del servidor: /var/www/html/$DIR"
echo "URL: $HOST"
echo "---Accesos---"
echo "Correo para administrador: admin@$HOST"
echo "Contraseña para administrador: $ADMIN_PASSWORD"
echo "---MYSQL---"
echo "Nombre: $MYSQL_DATABASE"
echo "Usuario: $MYSQL_USER"
echo "Contraseña: $MYSQL_PASSWORD"
echo "---Clave---"
cat /var/www/html/$DIR/ssh/id_rsa.pub