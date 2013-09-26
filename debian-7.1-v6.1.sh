#!/bin/bash
# Unattended GitLab Installation for Debian 7.1 64-Bit
#
# Maintainer: @caseyscarborough
# GitLab Version: 6.1
#
# This script installs GitLab server on Debian 7.1 with all dependencies.
#
# USAGE
# This script must be run as the root user on a fresh install of Debian 7.1.
# You may also need to install curl with `apt-get install curl`
# curl https://raw.github.com/caseyscarborough/gitlab-install/master/debian-7.1-v6.1.sh | DOMAIN_VAR=gitlab.example.com bash

GITLAB_USER=git
GITLAB_USER_ROOT=/home/$GITLAB_USER
GITLAB_ROOT=$GITLAB_USER_ROOT/gitlab
GITLAB_URL="http:\/\/$DOMAIN_VAR\/"

# Check for domain variable.
if [ $DOMAIN_VAR ]; then
  echo -e "*==================================================================*\n"
  echo -e " GitLab Installation has begun!\n"
  echo -e "   Domain: $DOMAIN_VAR"
  echo -e "   GitLab URL: http://$DOMAIN_VAR/"
  echo -e "   Application Root: $GITLAB_ROOT\n"
  echo -e "*==================================================================*\n"
  sleep 3
else
  echo "Please specify DOMAIN_VAR when running the script. See below:"
  echo "curl debian-7.1-v6.1.sh | DOMAIN_VAR=gitlab.example.com bash"
  exit
fi

## 
# Installing Packages
#
echo -e "\n*== Installing new packages...\n"
apt-get update -y
apt-get upgrade -y
apt-get install -y sudo build-essential makepasswd zlib1g-dev libyaml-dev libssl-dev libgdbm-dev libreadline-dev libncurses5-dev libffi-dev curl git-core openssh-server redis-server checkinstall libxml2-dev libxslt-dev libcurl4-openssl-dev libicu-dev python-docutils

# Generate passwords for MySQL root and gitlab users.
MYSQL_ROOT_PASSWORD=$(makepasswd --char=25)
MYSQL_GIT_PASSWORD=$(makepasswd --char=25)

##
# Download and compile Ruby
#
echo -e "\n*== Downloading and configuring Ruby...\n"
mkdir /tmp/ruby
cd /tmp/ruby
curl --progress ftp://ftp.ruby-lang.org/pub/ruby/2.0/ruby-2.0.0-p247.tar.gz | tar xz
cd ruby-2.0.0-p247
./configure
make
make install

# Create git user.
adduser --disabled-login --gecos 'GitLab' $GITLAB_USER

echo -e "\n*== Installing MySQL Server...\n"
echo mysql-server mysql-server/root_password password $MYSQL_ROOT_PASSWORD | sudo debconf-set-selections
echo mysql-server mysql-server/root_password_again password $MYSQL_ROOT_PASSWORD | sudo debconf-set-selections
apt-get install -y mysql-server mysql-client libmysqlclient-dev

mysql -u root -p$MYSQL_ROOT_PASSWORD -e "CREATE USER 'gitlab'@'localhost' IDENTIFIED BY '$MYSQL_GIT_PASSWORD';"
mysql -u root -p$MYSQL_ROOT_PASSWORD -e "CREATE DATABASE IF NOT EXISTS gitlabhq_production DEFAULT CHARACTER SET utf8 COLLATE utf8_unicode_ci;"
mysql -u root -p$MYSQL_ROOT_PASSWORD -e "GRANT SELECT, LOCK TABLES, INSERT, UPDATE, DELETE, CREATE, DROP, INDEX, ALTER ON gitlabhq_production.* TO 'gitlab'@'localhost';"

##
# Set up the Git configuration.
#
echo -e "\n*== Configuring Git..."
sudo -u $GITLAB_USER -H git config --global user.name "GitLab"
sudo -u $GITLAB_USER -H git config --global user.email "gitlab@localhost"
sudo -u $GITLAB_USER -H git config --global core.autocrlf input

## 
# Install GitLab Shell
#
echo -e "\n*== Installing GitLab Shell...\n"
cd $GITLAB_USER_ROOT
sudo -u $GITLAB_USER -H git clone https://github.com/gitlabhq/gitlab-shell.git
cd gitlab-shell
sudo -u $GITLAB_USER -H git checkout v1.7.1
sudo -u $GITLAB_USER -H cp config.yml.example config.yml
sed -i 's/http:\/\/localhost\//'$GITLAB_URL'/' /home/git/gitlab-shell/config.yml
sudo -u $GITLAB_USER -H ./bin/install

## 
# Install GitLab
#
echo -e "\n*== Installing GitLab...\n"
cd $GITLAB_USER_ROOT
sudo -u $GITLAB_USER -H git clone https://github.com/gitlabhq/gitlabhq.git gitlab
cd $GITLAB_ROOT
sudo -u $GITLAB_USER -H git checkout 6-1-stable
sudo -u $GITLAB_USER -H mkdir $GITLAB_USER_ROOT/gitlab-satellites
sudo -u $GITLAB_USER -H cp $GITLAB_ROOT/config/gitlab.yml.example $GITLAB_ROOT/config/gitlab.yml
sed -i "s/host: localhost/host: ${DOMAIN_VAR}/" $GITLAB_ROOT/config/gitlab.yml
sudo -u $GITLAB_USER cp config/database.yml.mysql config/database.yml
sed -i 's/username: root/username: gitlab/' $GITLAB_ROOT/config/database.yml
sed -i 's/"secure password"/"'$MYSQL_GIT_PASSWORD'"/' $GITLAB_ROOT/config/database.yml
sudo -u $GITLAB_USER -H chmod o-rwx config/database.yml
sudo -u $GITLAB_USER -H cp config/unicorn.rb.example config/unicorn.rb

##
# Install required Gems.
#
echo -e "\n*== Installing required gems...\n"
gem install bundler --no-ri --no-rdoc
sudo -u $GITLAB_USER -H bundle install --deployment --without development test postgres aws

##
# Update permissions.
#
echo -e "\n*== Updating permissions..."
sudo -u $GITLAB_USER -H mkdir tmp/pids/
sudo -u $GITLAB_USER -H mkdir tmp/sockets/
sudo -u $GITLAB_USER -H mkdir public/uploads
chown -R $GITLAB_USER log/
chown -R $GITLAB_USER tmp/
chmod -R u+rwX log/
chmod -R u+rwX tmp/
chmod -R u+rwX tmp/pids/
chmod -R u+rwX tmp/sockets/
chmod -R u+rwX public/uploads

##
# Run setup and add startup script.
#
sed -i 's/ask_to_continue/# ask_to_continue/' lib/tasks/gitlab/setup.rake
sudo -u $GITLAB_USER -H bundle exec rake gitlab:setup RAILS_ENV=production
sed -i 's/# ask_to_continue/ask_to_continue/' lib/tasks/gitlab/setup.rake
cp lib/support/init.d/gitlab /etc/init.d/gitlab
chmod +x /etc/init.d/gitlab
update-rc.d gitlab defaults 21

##
# Nginx installation
#
echo -e "\n*== Installing Nginx...\n"
apt-get install -y nginx
cp lib/support/nginx/gitlab /etc/nginx/sites-available/gitlab
ln -s /etc/nginx/sites-available/gitlab /etc/nginx/sites-enabled/gitlab
sed -i "s/YOUR_SERVER_FQDN/${DOMAIN_VAR}/" /etc/nginx/sites-enabled/gitlab
sed -i "s/127.0.0.1\tlocalhost/127.0.0.1\t${DOMAIN_VAR}/" /etc/hosts

# Start GitLab and Nginx!
echo -e "\n*== Starting Gitlab!\n"
service gitlab start
service nginx restart

echo -e "root: ${MYSQL_ROOT_PASSWORD}\ngitlab: ${MYSQL_GIT_PASSWORD}" > $GITLAB_ROOT/config/mysql.yml
sudo -u $GITLAB_USER -H chmod o-rwx $GITLAB_ROOT/config/database.yml

echo -e "*==================================================================*\n"
echo -e " GitLab has been installed successfully!"
echo -e " Navigate to $DOMAIN_VAR in your browser to access the application.\n"
echo -e " Login with the default credentials:"
echo -e "   admin@local.host"
echo -e "   5iveL!fe\n"
echo -e " Your MySQL username and passwords are located in the following file:"
echo -e "   $GITLAB_ROOT/config/mysql.yml\n"
echo -e " Script written by Casey Scarborough, 2013."
echo -e " https://github.com/caseyscarborough\n"
echo -e "*==================================================================*"