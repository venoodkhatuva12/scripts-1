#!/bin/bash
#
# Installation script for a readthedocs dev/prod server
# starting from a plain and clean CENTOS box.
# readthedocs.org (rtd)
#
# Script actions:
# - Disables iptables
# - Installs epel repo
# - Installs dependencies (including whole DEV env and latex)
# - Installs python pip
# - Installs python2.7
# - Installs readthedocs (rtd)
# - Installs gunicorn/nginx
# - Modifies /etc/hosts
#
#
# Avg installation time in Centos 6.4 vagrant box with
# 500MB RAM, 1 CPU @ 2.30GHz, 2GB hard-drive: (indicative)
#     - ~13 min
#
#
# Author: luismartingil
# Website: www.luismartingil.com
# Year: 2014
#
# Helped by this post: 
# - http://pfigue.github.io/blog/2013/03/23/read-the-docs-served-standalone-with-gunicorn/
#

# Working dir, make sure this location is unique
DIR=/opt/rtd_local

# Some other folder definitions
ENV=rtd
ENV_DIR=$DIR/$ENV
ENV_PYTHON_BIN=$ENV_DIR/bin/python
ENV_GUNICORN_BIN=$ENV_DIR/bin/gunicorn
RTD_DIR=$ENV_DIR/checkouts/readthedocs.org
RTD_IN_DIR=$RTD_DIR/readthedocs/
RTD_SETTINGS_FILE=$RTD_IN_DIR/settings/local_settings.py

# =================================================
qquit () {
    echo "Usage: $0 <action>"
    echo "<action> {install|start-dev|start-gunicorn|stop-gunicorn}"
    exit 1
}

configure_django() {
    cat > $RTD_SETTINGS_FILE <<EOF
EMAIL_BACKEND = 'django.core.mail.backends.smtp.EmailBackend'
EMAIL_USE_TLS = True
EMAIL_HOST = 'smtp.gmail.com'
EMAIL_PORT = 587
# You need to activate the lesssecureapps if using google's smtp
# https://www.google.com/settings/security/lesssecureapps
EMAIL_HOST_USER = 'TODO@gmail.com'
EMAIL_HOST_PASSWORD = 'TODO'
DEFAULT_FROM_EMAIL = 'admin@docs.dev.net'
DEFAULT_TO_EMAIL = 'TODO'
SERVER_EMAIL = 'admin@docs.dev.net'
ADMINS = (('TODO', 'TODO@gmail.com'))
PRODUCTION_DOMAIN = 'docs.dev.net'
ALLOW_PRIVATE_REPOS = True
EOF
}

show_logs_available() {
    echo ' + Logs:'
    echo '     sudo tail -2222f /var/log/nginx/global-read-the-docs-access.log'
    echo '     sudo tail -2222f /var/log/nginx/global-read-the-docs-error.log'
    echo '     sudo tail -2222f '$RTD_DIR'/logs/rtd.log'
    echo ''
}

rtd_is_installed() {
  # Needs to improve this condition
  if [ -d "$DIR" ]; then
      return 0
  else
      return 1
  fi
}

setup_working_folder() {
    cd /tmp
    if [ -d "$DIR" ]; then
	sudo rm -fr $DIR
    fi
    sudo mkdir -p $DIR
    sudo chown -R `whoami`:`whoami` $DIR
    cd $DIR
}

activate_python_virtualenv () {
    cd $ENV_DIR
    source bin/activate
}

rtd_manage () {
    # Manually asking to execute this commands.
    # In the future the --noinput option must be used,
    # so this will be automated.
    cd $RTD_DIR
    echo '-------------------------------------------------------------------'
    echo ' WARNING. Installation not completed yet.'
    echo '-------------------------------------------------------------------'
    echo '# Run these commands manually, please.'
    echo 'cd '$ENV_DIR
    echo 'source bin/activate'
    echo 'cd '$RTD_DIR
    echo ''
    echo '# Answer yes and create new user/pass.'
    echo $ENV_PYTHON_BIN' manage.py syncdb' # --noinput
    echo $ENV_PYTHON_BIN' manage.py migrate'
    #echo $ENV_PYTHON_BIN' manage.py test'
    echo $ENV_PYTHON_BIN' manage.py loaddata test_data'
    #echo $ENV_PYTHON_BIN' manage.py update_repos pip'
    echo 'deactivate'
    echo 'sudo chgrp -R nginx '$DIR
    echo ''
    echo '# Make sure virtualenv is placed where nginx can access, please.'
    echo 'namei -om '$ENV_DIR
    echo '-------------------------------------------------------------------'
}

configure_etc_hosts() {
    echo 'Configuring /etc/hosts including rtd'
    if [ `grep "docs" /etc/hosts | wc -l` -gt 0 ]
    then
	echo 'docs already in /etc/hosts'
    else
	for i in `hostname -I`; 
	do
	    sudo sh -c 'echo "'$i'   *.docs.dev.net docs.dev.net" >> /etc/hosts';
	done
	sudo sh -c 'echo "127.0.0.1   *.docs.dev.net docs.dev.net" >> /etc/hosts'
    fi
    cat /etc/hosts
}

install_configure_nginx () {
    echo 'Removing previous nginx installation, if any'
    sudo service nginx stop
    sudo yum remove -y nginx
    echo 'Installing nginx'
    sudo yum install -y nginx
    echo 'nginx installed'
    echo 'Configuring nginx adding readthedocs server'
    sudo mkdir /etc/nginx/site-enabled
    TMP_FILE=`mktemp`
    # WARNING. skipping $ symbols due to the cat command.
    cat > $TMP_FILE <<EOF
# -----------------------------
# server matching http://<project>.docs.dev.net
server {

   listen 80;
   server_name ~^(?<subdomain>.+)\.docs\.dev\.net\$;
   access_log  /var/log/nginx/global-read-the-docs-access.log;
   error_log   /var/log/nginx/global-read-the-docs-error.log;

   # Avoid 304 problem
   add_header Cache-Control public;
   # add_header Cache-Control no-cache;
   # if_modified_since off;
   add_header Last-Modified "";
   add_header ETag "";

   # Avoiding CSS problem
   # http://stackoverflow.com/a/11875443/851428
   include  /etc/nginx/mime.types;

   # Forward all media to gunicorn
   location ~ ^/media/(.*) {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
   }
   # If project.docs.dev.net/path, try to show master branch
   # To be changed: ___my_envrtd_dir___
   location / {
        alias ___my_envrtd_dir___/checkouts/readthedocs.org/user_builds/\$subdomain/rtd-builds/latest/;
   }
   # If project.docs.dev.net/en/branch/ or
   #    project.docs.dev.net/en/branch go to branch
   location ~ ^/en/(.+)(/?) {
        alias ___my_envrtd_dir___/checkouts/readthedocs.org/user_builds/\$subdomain/rtd-builds/\$1;
   }
   # If project.docs.dev.net/en/branch/path go to branch/path
   location ~ ^/en/(.+)/(.+) {
        alias ___my_envrtd_dir___/checkouts/readthedocs.org/user_builds/\$subdomain/rtd-builds/\$1/\$2;
   }
}

# -----------------------------
# server matching http://docs.dev.net
server {

   listen 80;
   server_name ~^docs\.dev\.net\$;
   access_log  /var/log/nginx/global-read-the-docs-access.log;
   error_log   /var/log/nginx/global-read-the-docs-error.log;

   # Avoid 304 problem
   add_header Cache-Control public;
   # add_header Cache-Control no-cache;
   # if_modified_since off;
   add_header Last-Modified "";
   add_header ETag "";

   # Avoiding CSS problem
   # http://stackoverflow.com/a/11875443/851428
   include  /etc/nginx/mime.types;

   # Forward everything to gunicorn
    location / {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
}
EOF
    sudo sed -i 's,___my_envrtd_dir___,'$ENV_DIR',g' $TMP_FILE
    sudo mv $TMP_FILE /etc/nginx/site-enabled/read-the-docs.localhost.conf
    sudo sed -i 's,include,#include,g' /etc/nginx/nginx.conf
    sudo sed -i '/http {/a include /etc/nginx/site-enabled/*.conf;' /etc/nginx/nginx.conf
    sudo /etc/init.d/nginx configtest
    sudo /etc/init.d/nginx stop
    sudo /etc/init.d/nginx start
    sudo chkconfig nginx on
    echo 'nginx configured for rtd'
}

install_other_pips () {
    pip install sphinx --upgrade
    pip install sphinxcontrib-seqdiag --upgrade
    pip install sphinxcontrib-httpdomain --upgrade
    pip install sphinx-bootstrap-theme --upgrade
    pip install sphinxjp.themes.basicstrap --upgrade
    pip install sphinxcontrib-tikz --upgrade
    pip install sphinxcontrib-doxylink --upgrade
    pip install sphinx_scruffy --upgrade
    pip install alabaster --upgrade
    pip install pygments --upgrade
    pip install gunicorn --upgrade
    pip install django-redis-cache --upgrade
    pip install greenlet --upgrade
    pip install gevent --upgrade
    pip install eventlet --upgrade
}

install_pip() {
    echo 'Installing pip'
    curl https://raw.githubusercontent.com/pypa/pip/master/contrib/get-pip.py | sudo python -
    echo 'Done installing pip'
    # Making sure this did the job
    hash pip 2>/dev/null || { echo >&2 "error installing pip."; exit 1; }
    echo 'Success installing pip'
}

install_epel() {
    echo 'Installing epel'
    sudo su -c 'rpm -Uvh http://dl.fedoraproject.org/pub/epel/6/x86_64/epel-release-6-8.noarch.rpm'
    echo 'Done installing epel'
}

install_req () {
    echo 'Installing dependencies'
    # Getting epel repo
    [ `ls -lart /etc/yum.repos.d/ | grep epel | wc -l` -gt 0 ] && echo 'epel repo already installed' || install_epel
    # Getting dependencies
    sudo yum groupinstall -y "Development tools"
    sudo yum install -y texlive-* pdfjam python-devel libxml2 libxslt libxml2-devel libxslt-devel libyaml-devel lxml python-lxml libdbi-dbd-sqlite zlib-devel xz-devel zlib-dev ncurses-devel bzip2-devel openssl-devel libpcap-devel readline-devel python-sqlite2 tk-devel gdbm-devel db4-devel sqlite-devel
    # Installing tikz and graphviz plugin requirements
    sudo yum install -y netpbm netpbm-devel ImageMagick poppler poppler-utils  pypoppler tex-preview mimetex doxygen graphviz plotutils-devel plotutils librsvg2-devel librsvg2 thai-scalable-purisa-fonts
    # Installing pip
    hash pip 2>/dev/null && echo 'pip already installed' || install_pip
    echo 'Done installing dependencies'
}

install_python27_aux () {
    echo 'Installing python2.7'
    # Installing python2.7
    wget --no-check-certificate http://python.org/ftp/python/2.7.6/Python-2.7.6.tgz
    gzip -dc Python-2.7.6.tgz | tar xf -
    cd Python-2.7.6
    ./configure --prefix=/usr/local --enable-unicode=ucs4 --enable-shared LDFLAGS="-Wl,-rpath /usr/local/lib"
    make && sudo make altinstall
    which python2.7
    echo 'Done installing python2.7'
    # Making sure this did the job
    hash python2.7 2>/dev/null || { echo >&2 "Error installing python2.7."; exit 1; }
    echo 'Success installing python2.7'
}

install_python27 () {
    hash python2.7 2>/dev/null && echo 'python2.7 already installed' || install_python27_aux
}

install_rtd_core () {
    echo 'Installing rtd'
    echo 'Removing previous installation'
    sudo rm -fr $ENV_DIR
    sudo pip install setuptools --upgrade
    sudo pip install virtualenv --upgrade
    virtualenv -p python2.7 $ENV_DIR
    activate_python_virtualenv
    mkdir checkouts ; cd checkouts
    git clone https://github.com/rtfd/readthedocs.org.git
    cd readthedocs.org
    echo 'Installing rtd reqs'
    pip install pip --upgrade
    pip install -r pip_requirements.txt
    install_other_pips
    echo 'Done installing rtd reqs'
    install_configure_nginx
    configure_etc_hosts
    echo ' ------------------ '
    rtd_manage
    configure_django
    echo 'Please edit: '$RTD_SETTINGS_FILE
    echo 'Done installing rtd'
    echo ' + Working directoy: "'$DIR'"'
    echo ' + Python virtualenv location: "'$ENV_DIR'"'
    echo ''
}
# =================================================

# -------------------------------------------------
do_install () {
    if rtd_is_installed; then
	echo 'local rtd already installed, quitting...'
	exit
    fi
    # No iptables, please
    sudo service iptables stop
    sudo chkconfig iptables off
    # Setup working folder
    setup_working_folder
    # Installing requirements
    cd $DIR ; install_req
    # Installing python2.7 if needed
    cd $DIR ; install_python27
    # Installing rtd from Python sources
    cd $DIR ; install_rtd_core
}
# -------------------------------------------------

# -------------------------------------------------
do_start_dev () {
    activate_python_virtualenv
    cd $RTD_DIR
    echo 'Running rtd server!'
    $ENV_PYTHON_BIN manage.py runserver 0.0.0.0:8000
}
# -------------------------------------------------

# -------------------------------------------------
do_start_gunicorn () {
    activate_python_virtualenv
    cd $RTD_DIR
    echo 'Running rtd server with gunicorn!'
    export PYTHONPATH=$RTD_DIR':'$RTD_IN_DIR
    export DJANGO_SETTINGS_MODULE='readthedocs.settings.sqlite'
    $ENV_GUNICORN_BIN -w 2 --threads 4 -k gevent --worker-connections=2000 --backlog=1000 --log-level=info --daemon -p $RTD_DIR/gunicorn.pid readthedocs.wsgi:application # --debug
}
# -------------------------------------------------

# -------------------------------------------------
do_stop_gunicorn () {
    echo 'Stopping guinicorn!'
    if [ `ps aux | grep -e gunicorn -e readthedocs.wsgi  | wc -l` -gt 0 ]
    then
	kill `cat $RTD_DIR/gunicorn.pid`
    else
	echo 'no read-the-docs gunicorn running'
    fi
}
# -------------------------------------------------


# =================================================
# Main
T1=$(date +%s)
case $1 in
    install)
	do_install
	;;
    start-dev)
	do_start_dev
	;;
    start-gunicorn)
	do_start_gunicorn
	;;
    stop-gunicorn)
	do_stop_gunicorn
	;;
    *)
	qquit
	;;
esac
T2=$(date +%s)
diffsec="$(expr $T2 - $T1)"
echo | awk -v D=$diffsec '{printf "Elapsed time: %02d:%02d:%02d\n",D/(60*60),D%(60*60)/60,D%60}'
show_logs_available
# =================================================
