#!/bin/bash

HOST=${1:-'dominio'}
#parametros opcionales
PROYECT=${2:-'https://gitlab.com/b.mendoza/facturadorpro3.git'}
REMOTE='git@gitlab.com:'$(echo $PROYECT | sed -e s#^https://gitlab.com/##)
SERVICE_NUMBER=${3:-'1'}
DIR=$(echo $PROYECT | rev | cut -d'/' -f1 | rev | cut -d '.' -f1)$SERVICE_NUMBER
MYSQL_PORT_HOST=${4:-'3306'}
MYSQL_USER=${5:-$DIR}
MYSQL_PASSWORD=${6:-$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 20 ; echo '')}
MYSQL_DATABASE=${7:-$DIR}
ADMIN_PASSWORD=${8:-$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 10 ; echo '')}
EMAIL=${9:-'frank921713@hotmail.com'}

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

echo "Instalando servidor web"
add-apt-repository ppa:ondrej/php -y
apt-get -y update
apt-get -y install php7.2 php7.2-mbstring php7.2-soap php7.2-zip php7.2-mysql php7.2-curl php7.2-gd php7.2-xml

echo "Instalando mysql"
apt-get -y install mysql-server-5.7 mysql-client-5.7

mysql -uroot <<MYSQL_SCRIPT
CREATE DATABASE $MYSQL_DATABASE;
CREATE USER '$MYSQL_USER'@'localhost' IDENTIFIED BY '$MYSQL_PASSWORD';
GRANT ALL PRIVILEGES ON * . * TO '$MYSQL_USER'@'localhost';
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
            'name' => 'Admin Instrador',
            'email' => 'admin@$HOST',
            'password' => bcrypt('$ADMIN_PASSWORD'),
        ]);
 

        DB::table('plan_documents')->insert([
            ['id' => 1, 'description' => 'Facturas, boletas, notas de d??bito y cr??dito, res??menes y anulaciones' ],
            ['id' => 2, 'description' => 'Guias de remisi??n' ],
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

echo "Cconfigurando $HOST"
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

echo "Finalizado el despliegue"


echo "Ruta del proyecto dentro del servidor: /var/www/$DIR"
echo "URL: $HOST"
echo "---Accesos---"
echo "Correo para administrador: admin@$HOST"
echo "Contrase??a para administrador: $ADMIN_PASSWORD"
echo "---MYSQL---"
echo "Nombre: $MYSQL_DATABASE"
echo "Usuario: $MYSQL_USER"
echo "Contrase??a: $MYSQL_PASSWORD"
echo "---Clave---"
cat /var/www/html/$DIR/ssh/id_rsa.pub