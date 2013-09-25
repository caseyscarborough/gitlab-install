# GitLab Automated Installation

This repository holds scripts that will perform automated installation of [GitLab](http://gitlab.org) on your server. Currently the only supported system is Ubuntu Server 12.04 running the latest version of GitLab, 6.1.

## Usage

You can run the script on your server by issuing the following command. Make sure to specify your domain name for the GitLab server using the `DOMAIN_VAR` environment variable.

```bash
curl https://raw.github.com/caseyscarborough/gitlab-install/master/ubuntu-server-12.04-v6.1.sh | sudo DOMAIN_VAR=gitlab.example.com bash
```