#!/bin/bash
# Unattended GitLab Installation for Ubuntu Server 12.04 and 13.04 64-Bit
#
# Maintainer: @caseyscarborough
# GitLab Version: 6.7
#
# This script installs GitLab server on Ubuntu Server 12.04 or 13.04 with all dependencies.
#
# INFORMATION
# Distribution      : Ubuntu 12.04 & 13.04 64-Bit
# GitLab Version    : 6.7
# Web Server        : Nginx
# Init System       : systemd
# Database          : PostgreSQL (default) or MySQL
# Contributors      : @caseyscarborough
#
# USAGE
#   wget -O ~/ubuntu-server-12.04.sh https://raw.github.com/caseyscarborough/gitlab-install/master/ubuntu-server-12.04.sh
#   sudo bash ~/ubuntu-server-12.04.sh -d gitlab.example.com (--mysql OR --postgresql)

help_menu ()
{
  echo "Usage: $0 -d DOMAIN_VAR (-m|--mysql)|(-p|--postgresql)"
  echo "  -h,--help        Display this usage menu"
  echo "  -d,--domain-var  Set the domain variable for GitLab, e.g. gitlab.example.com"
  echo "  -p,--postgresql  Use PostgreSQL as the database (default)"
  echo "  -m,--mysql       Use MySQL as the database (not recommended)"
}

# Set the application user and home directory.
APP_USER=git
USER_ROOT=/home/$APP_USER
DATABASE_TYPE="PostgreSQL"

# Set the application root.
APP_ROOT=$USER_ROOT/gitlab

# Get the variables from the command line.
while test $# -gt 0; do
  case "$1" in
    -h|--help)
      help_menu
      exit 0
      ;;
    -d|--domain-var)
      shift
      if test $# -gt 0; then
        DOMAIN_VAR=$1
      else 
        echo "No domain variable was specified."
        help_menu
        exit 1
      fi
      shift
      ;;
    -m|--mysql)
      shift
      DATABASE_TYPE="MySQL"
      ;;
    -p|--postgresql)
      shift
      DATABASE_TYPE="PostgreSQL"
      ;;
    *)
      echo "Unknown argument: $1"
      exit 1
      ;;
  esac
done

# Check for domain variable.
if [ $DOMAIN_VAR ]; then
  echo -e "*==================================================================*\n"

  echo -e " GitLab Installation has begun!\n"
  
  echo -e "   Domain: $DOMAIN_VAR"
  echo -e "   GitLab URL: http://$DOMAIN_VAR/"
  echo -e "   Application Root: $APP_ROOT"
  echo -e "   Database Type: $DATABASE_TYPE\n"
  
  echo -e "*==================================================================*\n"
  sleep 3
else
  echo "Please specify DOMAIN_VAR using the -d flag."
  help_menu
  exit 1
fi

## 
# Installing Packages
#
echo -e "\n*== Installing new packages...\n"
sudo apt-get update -y 2>&1 >/dev/null
sudo apt-get upgrade -y
sudo apt-get install -y build-essential makepasswd zlib1g-dev libyaml-dev libssl-dev libgdbm-dev libreadline-dev libncurses5-dev libffi-dev curl git-core openssh-server redis-server checkinstall libxml2-dev libxslt-dev libcurl4-openssl-dev libicu-dev python-docutils python-software-properties sendmail logrotate

# Generate passwords for MySQL root and gitlab users.
MYSQL_ROOT_PASSWORD=$(makepasswd --char=25)
DB_USER_PASSWORD=$(makepasswd --char=25)

##
# Download and compile Ruby
#
echo -e "\n*== Downloading and configuring Ruby...\n"
mkdir -p /tmp/ruby && cd /tmp/ruby
curl --progress ftp://ftp.ruby-lang.org/pub/ruby/2.0/ruby-2.0.0-p353.tar.gz | tar xz
cd ruby-2.0.0-p353
./configure --disable-install-rdoc
make
sudo make install
sudo gem install bundler --no-ri --no-rdoc

# Add the git user.
sudo adduser --disabled-login --gecos 'GitLab' $APP_USER

if test $DATABASE_TYPE == "MySQL"; then
  ##
  # MySQL Installation
  # 
  echo -e "\n*== Installing MySQL Server...\n"
  echo mysql-server mysql-server/root_password password $MYSQL_ROOT_PASSWORD | sudo debconf-set-selections
  echo mysql-server mysql-server/root_password_again password $MYSQL_ROOT_PASSWORD | sudo debconf-set-selections
  sudo apt-get install -y mysql-server mysql-client libmysqlclient-dev

  # Secure the MySQL installation and add GitLab user and database.
  sudo echo -e "GRANT USAGE ON *.* TO ''@'localhost';
  DROP USER ''@'localhost';
  DROP DATABASE IF EXISTS test;
  CREATE USER 'git'@'localhost' IDENTIFIED BY '$DB_USER_PASSWORD';
  CREATE DATABASE IF NOT EXISTS gitlabhq_production DEFAULT CHARACTER SET utf8 COLLATE utf8_unicode_ci;
  GRANT SELECT, LOCK TABLES, INSERT, UPDATE, DELETE, CREATE, DROP, INDEX, ALTER ON gitlabhq_production.* TO 'git'@'localhost';
  " > /tmp/gitlab.sql
  mysql -u root -p$MYSQL_ROOT_PASSWORD -e "SOURCE /tmp/gitlab.sql"

  sudo rm /tmp/gitlab.sql
else
  ##
  # PostgreSQL Installation
  #
  sudo apt-get install -y postgresql-9.1 postgresql-client libpq-dev

  # Create user and database.
  sudo -u postgres psql -c "CREATE USER git WITH PASSWORD '$DB_USER_PASSWORD';"
  sudo -u postgres psql -c "CREATE DATABASE gitlabhq_production OWNER git;"
fi

##
# Update Git
#
echo -e "\n*== Updating Git...\n"
sudo add-apt-repository -y ppa:git-core/ppa
sudo apt-get update -y
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
sudo -u $APP_USER -H git clone https://gitlab.com/gitlab-org/gitlab-shell.git -b v1.9.1
cd gitlab-shell
sudo -u $APP_USER -H cp config.yml.example config.yml
sudo sed -i "s/localhost/$DOMAIN_VAR/" /home/git/gitlab-shell/config.yml
sudo -u $APP_USER -H ./bin/install

## 
# Install GitLab
#
echo -e "\n*== Installing GitLab...\n"
cd $USER_ROOT
sudo -u $APP_USER -H git clone https://gitlab.com/gitlab-org/gitlab-ce.git -b 6-7-stable gitlab
cd $APP_ROOT
sudo -u $APP_USER -H cp $APP_ROOT/config/gitlab.yml.example $APP_ROOT/config/gitlab.yml
sudo sed -i "s/host: localhost/host: ${DOMAIN_VAR}/" $APP_ROOT/config/gitlab.yml

if test $DATABASE_TYPE == 'MySQL'; then
  sudo -u $APP_USER cp $APP_ROOT/config/database.yml.mysql $APP_ROOT/config/database.yml
  sudo sed -i 's/username: root/username: gitlab/' $APP_ROOT/config/database.yml
  sudo sed -i 's/"secure password"/"'$DB_USER_PASSWORD'"/' $APP_ROOT/config/database.yml
else
  sudo -u $APP_USER cp $APP_ROOT/config/database.yml.postgresql $APP_ROOT/config/database.yml
  sudo sed -i 's/# username: git/username: git/' $APP_ROOT/config/database.yml
  sudo sed -i "s/# password:/password: '$DB_USER_PASSWORD'/" $APP_ROOT/config/database.yml
fi

sudo -u $APP_USER -H chmod o-rwx $APP_ROOT/config/database.yml

# Copy the example Unicorn config
sudo -u $APP_USER -H cp $APP_ROOT/config/unicorn.rb.example $APP_ROOT/config/unicorn.rb

# Set the timeout to 300
sudo sed -i 's/timeout 30/timeout 300/' $APP_ROOT/config/unicorn.rb
sudo sed -i 's/error_log   /var/log/nginx/gitlab_error.log;/error_log   /var/log/nginx/gitlab_error.log;\n\nproxy_connect_timeout 300;\nproxy_read_timeout 300;/' /etc/nginx/sites-available/gitlab

# Copy the example Rack attack config
sudo -u $APP_USER -H cp $APP_ROOT/config/initializers/rack_attack.rb.example $APP_ROOT/config/initializers/rack_attack.rb

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

if test $DATABASE_TYPE == 'MySQL'; then
  sudo -u $APP_USER -H bundle install --deployment --without development test postgres aws
else
  sudo -u $APP_USER -H bundle install --deployment --without development test mysql aws
fi

##
# Run setup and add startup script.
#
sudo sed -i 's/ask_to_continue/# ask_to_continue/' $APP_ROOT/lib/tasks/gitlab/setup.rake
sudo -u $APP_USER -H bundle exec rake gitlab:setup RAILS_ENV=production
sudo sed -i 's/# ask_to_continue/ask_to_continue/' $APP_ROOT/lib/tasks/gitlab/setup.rake

sudo cp $APP_ROOT/lib/support/init.d/gitlab /etc/init.d/gitlab
sudo chmod +x /etc/init.d/gitlab
sudo update-rc.d gitlab defaults 21

# Setup logrotate
sudo cp $APP_ROOT/lib/support/logrotate/gitlab /etc/logrotate.d/gitlab

# Check application status
sudo -u $APP_USER -H bundle exec rake gitlab:env:info RAILS_ENV=production

##
# Nginx installation
#
echo -e "\n*== Installing Nginx...\n"
sudo apt-get install -y nginx
sudo cp $APP_ROOT/lib/support/nginx/gitlab /etc/nginx/sites-available/gitlab
sudo ln -s /etc/nginx/sites-available/gitlab /etc/nginx/sites-enabled/gitlab
sudo sed -i "s/YOUR_SERVER_FQDN/${DOMAIN_VAR}/" /etc/nginx/sites-available/gitlab
sudo sed -i "s/127.0.0.1\tlocalhost/127.0.0.1\tlocalhost\n127.0.0.1\t${DOMAIN_VAR}/" /etc/hosts

# Set timeout to 300
sudo sed -i 's/gitlab_error.log;/gitlab_error.log;\n\n  proxy_connect_timeout 300;\n  proxy_read_timeout 300;/' /etc/nginx/sites-available/gitlab

# Start GitLab and Nginx!
echo -e "\n*== Starting Gitlab!\n"
sudo service gitlab start
sudo service nginx restart

if test $DATABASE_TYPE == 'MySQL'; then
  sudo echo -e "root: $MYSQL_ROOT_PASSWORD\ngitlab: $DB_USER_PASSWORD" > $APP_ROOT/config/mysql.yml
else
  sudo echo -e "git: $DB_USER_PASSWORD" > $APP_ROOT/config/postgresql.yml
fi

# Double check application status
sudo -u $APP_USER -H bundle exec rake gitlab:check RAILS_ENV=production

echo -e "*==================================================================*\n"

echo -e " GitLab has been installed successfully!"
echo -e " Navigate to $DOMAIN_VAR in your browser to access the application.\n"

echo -e " Login with the default credentials:"
echo -e "   admin@local.host"
echo -e "   5iveL!fe\n"

if test $DATABASE_TYPE == 'MySQL'; then
  echo -e " Your MySQL username and passwords are located in the following file:"
  echo -e "   $APP_ROOT/config/mysql.yml\n"
else
  echo -e " Your PostgreSQL username and password is located in the following file:"
  echo -e "   $APP_ROOT/config/postgresql.yml\n"
fi

echo -e " Script written by Casey Scarborough, 2014."
echo -e " https://github.com/caseyscarborough\n"

echo -e "*==================================================================*"
