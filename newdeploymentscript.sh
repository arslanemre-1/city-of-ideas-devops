#!/bin/bash

# This file is part of City of ideas project
# Functie: Script for deploying to Google Cloud
# Arguments: -delete -deletall -import
# Auteur: Emre Arslan - emre.arslan.1@student.kdg.be
# Copyright: 2019 emre.arslan.1@student.kdg.be
# Versie: 1.0.0
# Requires: Standaard shell find commando, Gcloud sdk, env.json, coi_env.json
 

region="europe-west1"
zone="europe-west1-b"
database="city-of-ideas-db"
instance="city-of-ideas-vm"
firewall="https"
firewall2="mqtt"
sql="city-of-ideas-sql$((200 + RANDOM % 2**16))"
bucket="city-of-ideas-bucket"
static="city-of-ideas-ip"
user=$(cat user.txt)
password=$(cat pw.txt)
bucketdumpfile="CityOfIdeasDB.gz"
projects=$(gcloud projects list| awk '{print $2}'|tail -n +2)
menu=($projects)
sqldel=$(gcloud sql instances list | sed -n 2p|awk '{print $1}')


function Help()
{

	printf "NAME 
    Deployment script - Script for deploying to Google Cloud using Compute Engine instance, MySql instance, Cloud storage.
    Contains also a MQTT broker that listens to topic KdG/Team10/CityOfIdeas.


DESCRIPTION
    Script for deploying to Google Cloud. gcloud vm will be started and run a startupscript that downloads the git repo. 
    Thereafter it will run it with dotnet and deploy it with NGINX.

GLOBAL FLAGS
	--help
        Display detailed help.

    --delete
        Deletes Compute Engine instance, MySql instance, Firewall rules. It will ask to export database to Cloud storage.  

    --deleteall
        Deletes Cloud Storage, static ip, Compute Engine instance, MySql instance, Firewall rules.
        It will ask to export database to Cloud storage.  


    --import
        Import data from Cloud storage to MySql database instance.

"

}



function Project()
{

gcloud -v &> /dev/null
if [ $? -eq 0 ]; then
	echo ""
else
	echo "Gcloud is not installed. Installing gcloud..."
	echo "deb http://packages.cloud.google.com/apt cloud-sdk-$(lsb_release -c -s) main" | sudo tee -a /etc/apt/sources.list.d/google-cloud-sdk.list
	curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -
	sudo apt-get update && sudo apt-get install google-cloud-sdk
	gcloud init

fi


echo "checking for updates.."
 gcloud components update --quiet &>/dev/null
echo "Please pick a project with a number"
select opt in "${menu[@]}"; do
         if [[ $opt = "" ]]; then
              echo "Please enter a valid number. Retry."
         else
              echo  "changing project to: $opt"; gcloud config set project $opt
          fi
          break
          done
}

function Deploy()
{
sqlip=$(gcloud sql instances list| sed -n 2p|awk '{print $5}')

echo '#!/bin/bash
(
sudo mkdir /var/www
cd /var/www
sudo git clone https://gitlab-ci-token:TnpgKEjYyu2dt7sE8yuf@gitlab.com/cityofideas/mqtt.git
sudo git clone https://gitlab-ci-token:TnpgKEjYyu2dt7sE8yuf@gitlab.com/cityofideas/web-application.git
cd web-application) 2>testgitmsql.txt

find /var/www -type f -exec chmod -R 0666 {} \;
sudo find /var/www -type d -exec chmod -R 2777 {} \;

sudo apt-add-repository ppa:mosquitto-dev/mosquitto-ppa
sudo apt-get update
sudo apt-get install -y mosquitto

sudo apt-get install -y mosquitto-clients


(sudo apt install -y gcc g++ build-essential
sudo apt install -y nginx) 2>nginx.txt

(wget -q https://packages.microsoft.com/config/ubuntu/18.04/packages-microsoft-prod.deb
sudo dpkg -i packages-microsoft-prod.deb
sudo apt-get install apt-transport-https
sudo apt-get update
sudo apt-get -y install dotnet-sdk-2.2) 2> tdotnetsdks.txt



sudo apt-get install python-software-properties python g++ make

(curl -sL https://deb.nodesource.com/setup_10.x | sudo -E bash -
sudo apt install -y nodejs) 2>nodejs.txt



(
cd /var/www/web-application/UI-MVC
npm install --unsafe-perm
npm run build

cd /var/www/mqtt
npm install --unsafe-perm
npm run build

(
sudo service nginx start

sudo echo "server {
 listen 80;
 server_name coi.invacto.com www.coi.invacto.com;
 location / {
   proxy_pass         http://localhost:5000;
        proxy_http_version 1.1;
        proxy_set_header   Upgrade \$http_upgrade;
        proxy_set_header   Connection keep-alive;
        proxy_set_header   Host \$host;
        proxy_cache_bypass \$http_upgrade;
        proxy_set_header   X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto \$scheme;
 }
}" > /etc/nginx/sites-available/default

sudo nginx -s reload) 2>init2.txt

echo "{ \"prod\": { \"SQL_IP\": \"'$sqlip'\", \"SQL_USER\": \"'$user'\", \"SQL_PW\": \"'$password'\", \"SQL_DB\": \"'$database'\" } }" > /var/www/web-application/UI-MVC/prod_env.json

sudo echo "[Unit]
Description=City of Ideas

[Service]

WorkingDirectory=/var/www/web-application/UI-MVC
ExecStart=/usr/bin/dotnet run --environment=Production
Restart=always
RestartSec=10 # Restart service after 10 seconds if dotnet service crashes
KillSignal=SIGINT
TimeoutStopSec=90
SyslogIdentifier=city-of-ideas
User=www-data

[Install]

WantedBy=multi-user.target
" > /etc/systemd/system/coi.service


  sudo echo  "[Unit]
  Description=MQTT-client

  [Service]

  WorkingDirectory=/var/www/mqtt
  ExecStart=/usr/bin/npm start
  Restart=always
  RestartSec=10 # Restart service after 10 seconds if npm service crashes
  KillSignal=SIGINT
  TimeoutStopSec=90
  SyslogIdentifier=city-of-ideas_mqtt
  User=www-data

  [Install]

  WantedBy=multi-user.target
  " > /etc/systemd/system/mqtt.service

sudo systemctl daemon-reload
sudo systemctl enable coi.service
sudo systemctl start coi.service
sudo systemctl enable mqtt.service
sudo systemctl start mqtt.service


sudo add-apt-repository -y ppa:certbot/certbot
sudo apt install -y python-certbot-nginx

sudo certbot --nginx -d coi.invacto.com --redirect -m emre.arslan.1@student.kdg.be --agree-tos --no-eff-email



)' > install_vm.sh

gcloud compute firewall-rules create $firewall --allow tcp:80
gcloud compute firewall-rules create $firewall2 --allow tcp:1883
sqlip=$(gcloud sql instances list --filter="name:$sql"|grep -E -o "([0-9]{1,3}[\.]){3}[0-9]{1,3}")
gcloud compute instances create $instance --machine-type=g1-small --image-project=ubuntu-os-cloud --image-family=ubuntu-1804-lts --zone=$zone --tags=chat,http-server,https-server --metadata-from-file startup-script=install_vm.sh
}

function Export()
{
serviceacc=$(gcloud sql instances describe $sqldel| grep serviceAccountEmailAddress| awk -v N=$N '{print $2}')
gsutil acl ch -u $serviceacc:W gs://$bucket
gcloud sql export sql $sqldel gs://$bucket/$bucketdumpfile \
                            --database=$database
gsutil acl ch -d $serviceacc gs://$bucket
}

function import()
{
serviceacc=$(gcloud sql instances describe $sql| grep serviceAccountEmailAddress| awk -v N=$N '{print $2}')
gsutil acl ch -u $serviceacc:W gs://$bucket
gsutil acl ch -u $serviceacc:R gs://$bucket/$bucketdumpfile
gcloud sql import sql $sql gs://$bucket/$bucketdumpfile --database=$database --quiet
gsutil acl ch -d $serviceacc gs://$bucket/$bucketdumpfile
gsutil acl ch -d $serviceacc gs://$bucket
}

function CreateBucket()
{
echo "init bucket"
gsutil mb gs://$bucket 2>/dev/null
}


function Delete()
{
while true; do
read -p "Do you wish to export the database to Cloud Storage? (y/n)" response
    case $(echo $response | tr '[A-Z]' '[a-z]') in
        y|yes)

if [[ $(gsutil ls) ]]; then
    echo "Exporting...."

	$(Export)
	echo "Deleting pls wait...."

	gcloud compute firewall-rules -q delete $firewall
	gcloud compute firewall-rules -q delete $firewall2
	gcloud compute instances -q delete $instance --zone=$zone
	gcloud sql instances -q delete $sqldel;
	break;
else
    echo "U have no bucket! Creating bucket...."
	$(CreateBucket)
	    echo "Exporting...."

	$(Export)

		echo "Deleting pls wait...."

	gcloud compute firewall-rules -q delete $firewall
	gcloud compute firewall-rules -q delete $firewall2
	gcloud compute instances -q delete $instance --zone=$zone
	gcloud sql instances -q delete $sqldel;
	break;
fi;;
        n|no)     echo "Delete without export...";
	gcloud compute firewall-rules -q delete $firewall
	gcloud compute firewall-rules -q delete $firewall2
	gcloud compute instances -q delete $instance --zone=$zone;
	gcloud sql instances -q delete $sqldel; break ;;
	*)     echo "invalid option" ;;
    esac
done
}


function DeleteAll()
{
read -p "Are you sure you want to delete all?" response
    case $(echo $response | tr '[A-Z]' '[a-z]') in
        y|yes)
echo "Deleting...."
	gcloud compute firewall-rules -q delete $firewall
	gcloud compute firewall-rules -q delete $firewall2
	gcloud compute instances -q delete $instance --zone=$zone
	gcloud sql instances -q delete $sqldel
	gcloud compute addresses -q delete $static --region=$region
	gsutil rm -r gs://$bucket

;; * )
echo "Abort" ;;
esac
}



function Static()
{
echo "Checking for static ip "
if [ -z "$static" ]
then
"" &>/dev/null

else
reserved_ip_address=$(gcloud compute addresses list --filter="name:($static)"|grep -E -o "([0-9]{1,3}[\.]){3}[0-9]{1,3}")
if [[ $reserved_ip_address =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]
	then
gcloud compute instances delete-access-config $instance --zone=$zone
gcloud compute  instances add-access-config $instance --zone=$zone --address=$reserved_ip_address --network-tier=PREMIUM

	else
gcloud compute addresses create $static --description="CityOfIdeas reserved static ip" --region=$region --network-tier=PREMIUM
sleep 3s
gcloud compute instances delete-access-config $instance --zone=$zone
sleep 3s
reserved_ip_address=$(gcloud compute addresses list --filter="name:($static)"|grep -E -o "([0-9]{1,3}[\.]){3}[0-9]{1,3}")
gcloud compute instances add-access-config $instance --zone=$zone --address=$reserved_ip_address --network-tier=PREMIUM
	fi
fi
}


function CreateSql()
{
 echo "init sql plz wait..."
gcloud sql instances create $sql --tier=db-f1-micro --region=$region --backup 2> ERRORLOG.txt



if [ $? -eq 0 ]
then
  echo "Successfully created sql"
else
  echo "Timeout --> Resumed plz wait... "
	sleep 3
operation=$(gcloud sql operations  list --instance=$sql  |sed -n 2p | awk '{print $1;}')
	gcloud beta sql operations wait $operation 
fi

}

function DbAndUser()
{
gcloud sql databases create $database --instance=$sql
gcloud sql users create $user --instance=$sql --password=$password
gcloud sql instances patch $sql --quiet --authorized-networks=$reserved_ip_address
}



function JsonScp()
{
gcloud compute scp coi_env.json $instance:/var/www/web-application/UI-MVC/  --zone $zone
while [ $? -ne 0 ]; do
    gcloud compute scp coi_env.json $instance:/var/www/web-application/UI-MVC/  --zone $zone >>/dev/null
done
echo "Scp coi_en.json done!"

gcloud compute scp env.json $instance:/var/www/mqtt  --zone $zone
while [ $? -ne 0 ]; do
	gcloud compute scp env.json $instance:/var/www/mqtt --zone $zone
done
echo "Scp env.json done!"
}

##########main##########

if [ "$1" = "-h" ] || [ "$1" = "--help" ]
then
Help
elif [ "$1" = "-d" ] || [ "$1" = "--delete" ]
then
Delete
elif [ "$1" = "-da" ] || [ "$1" = "--deleteall" ]
then
DeleteAll
elif [ "$1" = "-i" ] || [ "$1" = "--import" ]
then
Project
CreateSql
import
Deploy
Static
DbAndUser
CreateBucket
JsonScp
gcloud compute instances list
else
Project
CreateSql
Deploy
Static
DbAndUser
CreateBucket
JsonScp
gcloud compute instances list
fi
