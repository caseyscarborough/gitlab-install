#!/bin/bash
# Unattended GitLab Installation for Ubuntu Server 12.04 and 13.04 64-Bit
#
# Maintainer: @caseyscarborough
# GitLab Version: 6.1
#
# This script installs GitLab server on Ubuntu Server 12.04 or 13.04 with all dependencies.
#
# INFORMATION
# Distribution      : Ubuntu 12.04 & 13.04 64-Bit
# GitLab Version    : 6.1
# Web Server        : Nginx
# Init System       : systemd
# Database          : MySQL
# Contributors      : @caseyscarborough
#
# USAGE
# curl https://raw.github.com/caseyscarborough/gitlab-install/master/ubuntu-server-12.04.sh | 
#   sudo DOMAIN_VAR=gitlab.example.com bash

# Set the application user and home directory.
APP_USER=git
USER_ROOT=/home/$APP_USER

# Set the application root.
APP_ROOT=$USER_ROOT/gitlab

# Set the URL for the GitLab instance.
GITLAB_URL="http:\/\/$DOMAIN_VAR\/"

# Check for domain variable.
if [ $DOMAIN_VAR ]; then
  echo -e "*==================================================================*\n"

  echo -e " GitLab Installation has begun!\n"
  
  echo -e "   Domain: $DOMAIN_VAR"
  echo -e "   GitLab URL: http://$DOMAIN_VAR/"
  echo -e "   Application Root: $APP_ROOT\n"
  
  echo -e "*==================================================================*\n"
  sleep 3
else
  echo "Please specify DOMAIN_VAR"
  exit
fi

## 
# Installing Packages
#
echo -e "\n*== Installing new packages...\n"
sudo apt-get update -y
sudo apt-get upgrade -y
sudo apt-get install -y build-essential makepasswd zlib1g-dev libyaml-dev libssl-dev libgdbm-dev libreadline-dev libncurses5-dev libffi-dev curl git-core openssh-server redis-server checkinstall libxml2-dev libxslt-dev libcurl4-openssl-dev libicu-dev python-docutils python-software-properties
# sudo DEBIAN_FRONTEND='noninteractive' apt-get install -y postfix-policyd-spf-python postfix

# Generate passwords for MySQL root and gitlab users.
MYSQL_ROOT_PASSWORD=$(makepasswd --char=25)
MYSQL_GIT_PASSWORD=$(makepasswd --char=25)

##
# Download and compile Ruby
#
echo -e "\n*== Downloading and configuring Ruby...\n"
mkdir /tmp/ruby && cd /tmp/ruby
curl --progress ftp://ftp.ruby-lang.org/pub/ruby/2.0/ruby-2.0.0-p247.tar.gz | tar xz
cd ruby-2.0.0-p247
./configure
make
sudo make install
sudo gem install bundler --no-ri --no-rdoc

# Add the git user.
sudo adduser --disabled-login --gecos 'GitLab' $APP_USER

##
# MySQL Installation
# 
echo -e "\n*== Installing MySQL Server...\n"
echo mysql-server mysql-server/root_password password $MYSQL_ROOT_PASSWORD | sudo debconf-set-selections
echo mysql-server mysql-server/root_password_again password $MYSQL_ROOT_PASSWORD | sudo debconf-set-selections
sudo apt-get install -y mysql-server mysql-client libmysqlclient-dev

# Secure the database.
mysql -u root -p$MYSQL_ROOT_PASSWORD -e "DROP USER ''@'localhost';"
mysql -u root -p$MYSQL_ROOT_PASSWORD -e "DROP DATABASE test;"

mysql -u root -p$MYSQL_ROOT_PASSWORD -e "CREATE USER 'gitlab'@'localhost' IDENTIFIED BY '$MYSQL_GIT_PASSWORD';"
mysql -u root -p$MYSQL_ROOT_PASSWORD -e "CREATE DATABASE IF NOT EXISTS gitlabhq_production DEFAULT CHARACTER SET utf8 COLLATE utf8_unicode_ci;"
mysql -u root -p$MYSQL_ROOT_PASSWORD -e "GRANT SELECT, LOCK TABLES, INSERT, UPDATE, DELETE, CREATE, DROP, INDEX, ALTER ON gitlabhq_production.* TO 'gitlab'@'localhost';"


##
# Update Git
#
echo -e "\n*== Updating Git...\n"
sudo add-apt-repository ppa:git-core/ppa
sudo apt-get update
sudo apt-get install -y git

##
# Set up the Git configuration.
#
echo -e "\n*== Configuring Git...\n"
sudo -u $APP_USER -H git config --global user.name "GitLab"
sudo -u $APP_USER -H git config --global user.email "gitlab@localhost"
sudo -u $APP_USER -H git config --global core.autocrlf input

## 
# Install GitLab Shell
#
echo -e "\n*== Installing GitLab Shell...\n"
cd $USER_ROOT
sudo -u $APP_USER -H git clone https://github.com/gitlabhq/gitlab-shell.git
cd gitlab-shell
sudo -u $APP_USER -H git checkout v1.7.1
sudo -u $APP_USER -H cp config.yml.example config.yml
sudo sed -i 's/http:\/\/localhost\//'$GITLAB_URL'/' /home/git/gitlab-shell/config.yml
sudo -u $APP_USER -H ./bin/install

## 
# Install GitLab
#
echo -e "\n*== Installing GitLab...\n"
cd $USER_ROOT
sudo -u $APP_USER -H git clone https://github.com/gitlabhq/gitlabhq.git gitlab
cd $APP_ROOT
sudo -u $APP_USER -H git checkout 6-1-stable
sudo -u $APP_USER -H mkdir $USER_ROOT/gitlab-satellites
sudo -u $APP_USER -H cp $APP_ROOT/config/gitlab.yml.example $APP_ROOT/config/gitlab.yml
sudo sed -i "s/host: localhost/host: ${DOMAIN_VAR}/" $APP_ROOT/config/gitlab.yml
sudo -u $APP_USER cp config/database.yml.mysql config/database.yml
sudo sed -i 's/username: root/username: gitlab/' $APP_ROOT/config/database.yml
sudo sed -i 's/"secure password"/"'$MYSQL_GIT_PASSWORD'"/' $APP_ROOT/config/database.yml
sudo -u $APP_USER -H chmod o-rwx config/database.yml
sudo -u $APP_USER -H cp config/unicorn.rb.example config/unicorn.rb

##
# Update permissions.
#
echo -e "\n*== Updating permissions...\n"
sudo -u $APP_USER -H mkdir tmp/pids/
sudo -u $APP_USER -H mkdir tmp/sockets/
sudo -u $APP_USER -H mkdir public/uploads
sudo chown -R $APP_USER log/
sudo chown -R $APP_USER tmp/
sudo chmod -R u+rwX log/
sudo chmod -R u+rwX tmp/
sudo chmod -R u+rwX tmp/pids/
sudo chmod -R u+rwX tmp/sockets/
sudo chmod -R u+rwX public/uploads

##
# Install required Gems.
#
echo -e "\n*== Installing required gems...\n"
cd $APP_ROOT
sudo gem install charlock_holmes --version '0.6.9.4'
sudo -u $APP_USER -H bundle install --deployment --without development test postgres aws

##
# Run setup and add startup script.
#
sudo sed -i 's/ask_to_continue/# ask_to_continue/' lib/tasks/gitlab/setup.rake
sudo -u $APP_USER -H bundle exec rake gitlab:setup RAILS_ENV=production
sudo sed -i 's/# ask_to_continue/ask_to_continue/' lib/tasks/gitlab/setup.rake
sudo cp lib/support/init.d/gitlab /etc/init.d/gitlab
sudo chmod +x /etc/init.d/gitlab
sudo update-rc.d gitlab defaults 21

##
# Nginx installation
#
echo -e "\n*== Installing Nginx...\n"
sudo apt-get install -y nginx
sudo cp lib/support/nginx/gitlab /etc/nginx/sites-available/gitlab
sudo ln -s /etc/nginx/sites-available/gitlab /etc/nginx/sites-enabled/gitlab
sudo sed -i "s/YOUR_SERVER_FQDN/${DOMAIN_VAR}/" /etc/nginx/sites-enabled/gitlab
sudo sed -i "s/127.0.0.1\tlocalhost/127.0.0.1\t${DOMAIN_VAR}/" /etc/hosts

# Start GitLab and Nginx!
echo -e "\n*== Starting Gitlab!\n"
sudo service gitlab start
sudo service nginx restart

sudo echo -e "root: ${MYSQL_ROOT_PASSWORD}\ngitlab: ${MYSQL_GIT_PASSWORD}" > $APP_ROOT/config/mysql.yml
sudo -u $APP_USER -H chmod o-rwx $APP_ROOT/config/database.yml

echo -e "*==================================================================*\n"

echo -e " GitLab has been installed successfully!"
echo -e " Navigate to $DOMAIN_VAR in your browser to access the application.\n"

echo -e " Login with the default credentials:"
echo -e "   admin@local.host"
echo -e "   5iveL!fe\n"

echo -e " Your MySQL username and passwords are located in the following file:"
echo -e "   $APP_ROOT/config/mysql.yml\n"

echo -e " Script written by Casey Scarborough, 2013."
echo -e " https://github.com/caseyscarborough\n"

echo -e "*==================================================================*"