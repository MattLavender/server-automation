#!/bin/bash

#if code didnot run properly copy pest the following command in the terminal
#sed -i 's/\r//' automation.sh  

#Colors settings
BLUE='\033[0;34m'
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color


#check permissions
if [[ $EUID -ne 0 ]]; then
    echo ""
    echo -e "${RED}[-] This script must be run as root! Login as root, sudo or su.${NC}" 
    echo ""
    exit 1;
fi

#remove disable swap, remove it and remove entry from fstab
function removeSwap(){
    echo -e "${YELLOW}[+] Removing swap and backup fstab.${NC}"
    echo ""

    #get the date time to help the scripts
    backupTime=$(date +%y-%m-%d--%H-%M-%S)

    #get the swapfile name
    swapSpace=$(swapon -s | tail -1 |  awk '{print $1}' | cut -d '/' -f 2)
    #debug: echo $swapSpace

    #turn off swapping
    swapoff /$swapSpace

    #make backup of fstab
    cp /etc/fstab /etc/fstab.$backupTime
    
    #remove swap space entry from fstab
    sed -i "/swap/d" /etc/fstab

    #remove swapfile
    rm -f "/$swapSpace"
    rm -f /swapfile;

    echo ""
    echo -e "${GREEN}[+] Removed old swap and save backup of your swap file at /etc/fstab /etc/fstab.$backupTime ${NC}"
    echo ""
}

#identifies available ram, calculate swap file size and configure
createSwap() {
    echo -e "${YELLOW}[+]Creating a swap and setup fstab.${NC}"
    echo ""

    #get available physical ram
    availMemMb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    #debug: echo $availMemMb
    
    #convert from kb to mb to gb
    gb=$(awk "BEGIN {print $availMemMb/1024/1204}")
    #debug: echo $gb
    
    #round the number to nearest gb
    gb=$(echo $gb | awk '{print ($0-int($0)<0.499)?int($0):int($0)+1}')
    #debug: echo $gb

    echo "[+] Available Physical RAM: $gb Gb"
    echo ""
    if [ $gb -eq 0 ]; then
        echo -e "${RED}[-]Something went wrong! Memory cannot be 0!${NC}"
        exit 1;
    fi

    if [ $gb -le 2 ]; then
        echo -e "${YELLOW}[+] Memory is less than or equal to 2 Gb${NC}"
        let swapSizeGb=$gb*2
        echo -e "${YELLOW}[+] Set swap size to $swapSizeGb Gb${NC}"
    fi
    if [ $gb -gt 2 -a $gb -lt 32 ]; then
        echo "${YELLOW}[+] Memory is more than 2 Gb and less than to 32 Gb.${NC}"
        let swapSizeGb=4+$gb-2
        echo -e "${YELLOW}[+] Set swap size to $swapSizeGb Gb.${NC}"
    fi
    if [ $gb -gt 32 ]; then
        echo -e "${YELLOW}[+] Memory is more than or equal to 32 Gb.${NC}"
        let swapSizeGb=$gb
        echo -e "${YELLOW}[+] Set swap size to $swapSizeGb Gb.${NC}"
    fi
    echo ""

    echo -e "${YELLOW}[+] Creating the swap file! This may take a few minutes...${NC}"
    echo ""

    #convert gb to mb to avoid error: dd-memory-exhausted-by-input-buffer-of-size-bytes
    let mb=$gb*1024

    #create swap file on root system and set file size to mb variable
    echo -e "${YELLOW}[+] Create swap file.${NC}"
    sudo fallocate -l ${swapSizeGb}G /swapfile
    dd if=/dev/zero of=/swapfile bs=1M count=$mb

    #set read and write permissions
    echo -e "${BLUE}[+] Swap file created setting up swap file permissions.${NC}"
    echo ""
    chmod 600 /swapfile

    #create swap area
    echo -e "${YELLOW}[+] Create swap area and trun it on.${NC}"
    echo ""
    mkswap /swapfile; swapon /swapfile
    #update the fstab
    if grep -q "swap" /etc/fstab; then
        echo -e "${RED}[-] The fstab contains a swap entry.${NC}"
        #do nothing
    else
        echo -e "${RED}[-] The fstab does not contain a swap entry. Adding an entry.${NC}"
        echo "/swapfile swap swap defaults 0 0" >> /etc/fstab    
    fi

    echo ""
    echo -e "${GREEN}[+] Done Press any Enter to go to home page.${NC}"
    echo ""
    read
}

#the main function that is run by the calling script.
function setupSwap() {
    #check if swap is on
    isSwapOn=$(swapon -s | tail -1)

    if [[ "$isSwapOn" == "" ]]; then
        echo -e  "${BLUE}[+] No swap has been configured! Will create.${NC}"
        echo ""

        createSwap
    else
        echo -e "${BLUE}[+] Swap has been configured. Will remove and then re-create the swap.${NC}"
        echo ""
        
        removeSwap
        createSwap
    fi
}

function setupSwapMain() {


    echo -e "${BLUE}[*] This will remove an existing swap file and then create a new one. "
    echo -e "[*] Please Know what you are doing first.${NC}"
    echo ""

    echo -n "Do you want to proceed? (Y/N): "; read proceed
    if [ "$proceed" == "y" ]; then
        echo "[+] setting up new swap memory"
        setupSwap
    else

        echo "Oke. Bye!"

    fi
}
########### virtual host ######
virtualHost(){
  default_domain="example.com"
  read -p "[+] Enter domain name default name [$default_domain]" name
  name="${name:-$default_domain}"
  echo $name
  DEFAULT_WEB_ROOT_DIR="/var/www/$name/public_html/"
  read -p "[+] Enter web root default  WEB_ROOT_DIR [$DEFAULT_WEB_ROOT_DIR]: " WEB_ROOT_DIR
    WEB_ROOT_DIR="${WEB_ROOT_DIR:-$DEFAULT_WEB_ROOT_DIR}"
    echo $WEB_ROOT_DIR

     
    email=${3-'webmaster@localhost'}
    sitesEnable='/etc/apache2/sites-enabled/'
    sitesAvailable='/etc/apache2/sites-available/'
    sitesAvailabledomain=$sitesAvailable$name.conf
    echo "[+] Creating a vhost for $sitesAvailabledomain with a webroot $WEB_ROOT_DIR"
    mkdir -p "$WEB_ROOT_DIR"
    sudo chown www-data:www-data -R "$WEB_ROOT_DIR"


    echo "
        <VirtualHost *:80>
          ServerAdmin $email
          ServerName $name
          DocumentRoot $WEB_ROOT_DIR
          <Directory $WEB_ROOT_DIR/>
            Options Indexes FollowSymLinks
            AllowOverride all
          </Directory>
        </VirtualHost>" > $sitesAvailabledomain
    echo -e $"\nNew Virtual Host Created\n"

    sed -i "1s/^/127.0.0.1 $name\n/" /etc/hosts

    a2ensite $name
    service apache2 reload

    echo -e "${GREEN}[+] Done, please browse to http://$name to check! Click enter to go to main menu.${NC}"
    read
}
virtualHostDelete(){
    default_domain="example.com"
    read -p "[+] Enter domain name default name [$default_domain]: " name
    name="${name:-$default_domain}"
     DEFAULT_WEB_ROOT_DIR="/var/www/$name"
  read -p "[+] Enter web root default  WEB_ROOT_DIR [$DEFAULT_WEB_ROOT_DIR]: " WEB_ROOT_DIR
    WEB_ROOT_DIR="${WEB_ROOT_DIR:-$DEFAULT_WEB_ROOT_DIR}"
    echo -e "${YELLOW}[+] Deleting web root dir $WEB_ROOT_DIR${NC}"
    rm -f -r "$WEB_ROOT_DIR"

    # sed -i "/[$name]/d" /etc/hosts
      sed -i "s/^.*$name.*$//" /etc/hosts
      echo -e  "${GREEN}[+]Removed name from hosts file${NC}"


    echo "[+] $name is deleted" 
    sitesEnable='/etc/apache2/sites-enabled/'
    sitesAvailable='/etc/apache2/sites-available/'
    sitesAvailabledomain=$sitesAvailable$name.conf
    echo -e "${YELLOW}[+] Deleting a vhost for $sitesAvailabledomain with a webroot $WEB_ROOT_DIR${NC}"

   rm -f $sitesAvailabledomain
    echo -e $"\n Virtual Host Deleted\n"
    a2dissite $name
    service apache2 reload

    echo -e "${GREEN}[+] Done, please browse to http://$name to check! Click enter to go to main menu.${NC}"
    read

}
installServerSetup(){
    echo -n -e "${YELLOW}[+] updating System first${NC}"
    sudo apt-get update -y && sudo apt-get upgrade -y
    echo -n -e "${YELLOW}[+] Installing apache2 server and its tools${NC}"
    sudo apt-get install apache2 apache2-doc apache2-mpm-prefork apache2-utils libexpat1 ssl-cert -y
    echo -n -e "${YELLOW}[+] Installing php and its tools${NC}"
    sudo apt-get install php libapache2-mod-php -y
    echo -n -e "${YELLOW}[+] Installing Mysql Database${NC}"
    sudo apt-get install mysql-server mysql-client -y
    echo -n -e "${YELLOW}[+] Installing Phpmyadmin${NC}"
    sudo apt-get install phpmyadmin -y
    echo -n -e "${YELLOW}[+] Changing permissions${NC}"
    sudo chown -R www-data:www-data /var/www
    echo ""
    echo -n -e "${YELLOW}[+] enable and restarting services${NC}"
    sudo service apache2 restart
    sudo service mysql restart
    sudo a2enmod rewrite
    sudo systemctl enable apache2
    sudo systemctl enable mysql
    sudo service apache2 restart
    sudo service mysql restart

}
phpmyadmin(){
    echo "[*] Please navigate using cd command where you want to install phpmysql"
    echo "[*] copy following command and pest in your console to install it mannally"
    echo "[*] Composer update"
    echo " -->  composer create-project phpmyadmin/phpmyadmin"
    echo " -->  composer create-project phpmyadmin/phpmyadmin --repository-url=https://www.phpmyadmin.net/packages.json --no-dev"
    read
}
updateSystem(){
    echo -e "${YELLOW}[+] Updating system.${NC}"
    apt-get update && apt-get upgrade -y
}
fullAutomatedWP(){
# Downloading wordpress
echo  -e "${YELLOW}[+] Downloading wordpress${NC}"
WORDPRESS_URL="https://wordpress.org/latest.tar.gz"

echo "[+] Project Location (eg. /home/users/name/desktop/)?"
read PROJECT_SOURCE_URL

# GET ALL USER INPUT
echo "[+] Project folder name?(if any)"
read PROJECT_FOLDER_NAME

echo "[+] Setup wp_config? (y/n)"
read SHOULD_SETUP_DB

if [ $SHOULD_SETUP_DB = 'y' ]
then
  echo "DB Name"
  read DB_NAME

  echo "DB Username"
  read DB_USERNAME

  echo "DB Password"
  read DB_PASSWORD
fi

#LETS START INSTALLING
echo  -e "${YELLOW}[+] Sit back and relax :) ......${NC}"

# CREATE PROJECT DIRECTORIES
mkdir -p "$PROJECT_SOURCE_URL"
cd "$PROJECT_SOURCE_URL"
echo "Creating $PROJECT_FOLDER_NAME"
mkdir -p "$PROJECT_FOLDER_NAME"
cd "$PROJECT_FOLDER_NAME"

# DOWNLOAD WORDPRESS
echo  -e "${YELLOW}Downloading Wordpress${NC}"
curl -O $WORDPRESS_URL

# UNZIP WORDPRESS AND REMOVE ARCHIVE FILES
echo -e  "${YELLOW}Unzipping Wordpress${NC}"
tar -xzf latest.tar.gz
rm -f latest.tar.gz
cd wordpress/
mv * ../
cd ..
rm -r wordpress

if [ $SHOULD_SETUP_DB = 'y' ]
then
  # SETUP WP CONFIG
  echo  -e "${YELLOW}[+] Create wp_config${NC}"
ls
  mv wp-config-sample.php wp-config.php

  sed -i "s/^.*DB_NAME.*$/define('DB_NAME', '$DB_NAME');/" wp-config.php
  sed -i "s/^.*DB_USER.*$/define('DB_USER', '$DB_USERNAME');/" wp-config.php
  sed -i "s/^.*DB_PASSWORD.*$/define('DB_PASSWORD', '$DB_PASSWORD');/" wp-config.php
  echo ""
  echo ""
   echo -e "${YELLOW}[+] creating database${NC}"
  MYSQL=`which mysql`

  Q1="CREATE DATABASE IF NOT EXISTS $DB_NAME;"
  Q2="GRANT ALL ON *.* TO '$DB_USERNAME'@'localhost' IDENTIFIED BY '$DB_PASSWORD';"
  Q3="FLUSH PRIVILEGES;"
  SQL="${Q1}${Q2}${Q3}"
  $MYSQL -uroot -e "$SQL"
  echo  -e "${Green}Database $DB_NAME and user $DB_USERNAME created with your password.${NC}"


fi

# REMOVE DEFAULT PLUGINS AND INSTALL WORDPRESS_PLUGIN_URL
# cd wp-content/plugins
# echo "Removing default plugins"
# rm hello.php
# rm -rf akismet
echo  -e "${GREEN}[+] All done press enter to continue${NC}"
read

}
programStart(){
while true; do 
    clear
    echo -e "${GREEN}               #########################################${NC}"
    echo -e "${GREEN}               ##                                     ##${NC}"
    echo -e "${GREEN}               ##       Credits:Sunil Sapkota         ##${NC}"
    echo -e "${GREEN}               ##   (Github: github.com/kismatboy)    ##${NC}"
    echo -e "${GREEN}               ##  (Tested on amazon EC2 ubuntu VM)   ##${NC}"
    echo -e "${GREEN}               ##                                     ##${NC}"
    echo -e "${GREEN}               #########################################${NC}"
    echo;echo;echo;echo;
    echo "[*] Welcome to the server management console"
    echo "[*] Enter 1 to install apache2 server and mysql server with phpmyadmin."
    echo "[*] Enter 2 to create swap Memory."
    echo "[*] Enter 3 to create virtual host."
    echo "[*] Enter 4 to Delete virtual host."
    echo "[*] Enter 5 to guide to install phpmyadmin mannally."
    echo "[*] Enter 6 to update your system."
    echo "[*] Enter 7 to install wordpress ."
    echo "[*] Any other number to exit."
    echo -n "[*] Enter Your choice: "
    read choice

    echo -n "[+] you choose $choice  Please wait we are doing it for you..."
    echo ""

    case $choice in

       1)
        installServerSetup
        ;; 
       2)
        setupSwapMain
        ;;

       3)
        virtualHost
        ;;

       4)
        virtualHostDelete
        ;;

       5)
        phpmyadmin
        ;;

       6)
        updateSystem
        ;;

       7)
        fullAutomatedWP
        ;;

      *)
        echo ""
        echo -n "Good Bye !"
        read 
        clear
        exit 1;
        ;;
    esac

done
}
programStart
