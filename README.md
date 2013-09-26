# GitLab Automated Installation

This repository holds scripts that will perform automated installation of [GitLab](http://gitlab.org) on your server.

## Supported Systems

These are currently the tested and supported systems.

* Ubuntu 12.04 64-Bit
* Ubuntu 13.04 64-Bit

## Usage

For Ubuntu 12.04 or 13.04 64-Bit, issue the following command, ensuring that you update the `DOMAIN_VAR` variable with your respective domain name:

```bash
curl https://raw.github.com/caseyscarborough/gitlab-install/master/ubuntu-server-v6.1.sh | sudo DOMAIN_VAR=gitlab.example.com bash
```

After the script runs, your installation of GitLab should be fully completed and ready to go. You can then navigate to the application using your server's domain name.

## Troubleshooting

If you run into problems, the first thing to check is to make sure that each file got it's proper configuration added. Everything listed below should happen automatedly, but there is always a chance for error. The following are the files to check and what should be set:

#### /home/git/gitlab-shell/config.yml

This file should have the gitlab_url set to the URL of your GitLab instance (with a trailing slash).

```bash
  gitlab_url: "http://gitlab.example.com/"
```

#### /home/git/gitlab/config/gitlab.yml

This file should have the hostname set under the web server settings.

```bash
gitlab:
  ## Web server settings
  host: gitlab.example.com
  port: 80
```

#### /home/git/gitlab/config/database.yml

This file should have the gitlab user and password for the database configuration.

```bash
production:
  username: gitlab
  password: kenvo2i3j0239urlks
```

#### /etc/nginx/sites-available/gitlab

This file should have the server name in the virtual host set to your domain.

```bash
server {
  listen *:80;
  server_name gitlab.example.com;
  server_token off;
  root /home/git/gitlab/public;
}
```