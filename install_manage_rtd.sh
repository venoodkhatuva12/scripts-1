#!/bin/bash
#
# Installation script for a readthedocs dev/prod server
# starting from a plain and clean CENTOS box.
# readthedocs.org (rtd)
#
# Script actions:
# - Disables iptables
# - Installs epel repo
# - Installs dependencies
# - Installs python pip
# - Installs python2.7
# - Installs readthedocs (rtd)
# - Installs gunicorn/nginx
# - Modifies /etc/hosts
#
#
# Avg installation time in Centos 6.4 vagrant box with
# 500MB RAM, 1 CPU @ 2.30GHz, 2GB hard-drive: 
#     - 
#
#
# Author: luismartingil
# Website: www.luismartingil.com
# Year: 2014
#
# Credits: http://pfigue.github.io/blog/2013/03/23/read-the-docs-served-standalone-with-gunicorn/
#

# Actual folder
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# Some other folder definitions
ENV=rtd
ENV_DIR=$DIR/$ENV
ENV_PYTHON_BIN=$ENV_DIR/bin/python
RTD_DIR=$ENV_DIR/checkouts/readthedocs.org
RTD_IN_DIR=$RTD_DIR/readthedocs/

# =================================================
qquit () {
    echo "Usage: $0 <action>"
    echo "<action> {install|run-dev|run-gunicorn}"
    exit 1
}

activate_python_virtualenv () {
    cd $ENV ; source bin/activate
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
    # Note skipping $ symbols
    cat > $TMP_FILE <<EOF
server {
    listen 80;
    server_name read-the-docs.localhost;
    access_log  /var/log/nginx/read-the-docs.localhost-access.log;
    error_log   /var/log/nginx/read-the-docs.localhost-error.log;

    location / {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
}
EOF
    sudo mv $TMP_FILE /etc/nginx/site-enabled/read-the-docs.localhost.conf
    sudo sed -i 's,include,#include,g' /etc/nginx/nginx.conf
    sudo sed -i '/http {/a include /etc/nginx/site-enabled/*.conf;' /etc/nginx/nginx.conf
    sudo /etc/init.d/nginx configtest
    sudo /etc/init.d/nginx stop
    sudo /etc/init.d/nginx start
    echo 'nginx configured for rtd'
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
    wget -c http://dl.fedoraproject.org/pub/epel/6/x86_64/epel-release-6-8.noarch.rpm
    wget -c http://rpms.famillecollet.com/enterprise/remi-release-6.rpm
    sudo rpm -Uvh remi-release-6*.rpm epel-release-6*.rpm
    echo 'Done installing epel'
}

install_req () {
    echo 'Installing dependencies'
    # Getting epel repo
    [ `ls -lart /etc/yum.repos.d/ | grep epel | wc -l` -gt 0 ] && echo 'epel repo already installed' || install_epel
    # Getting dependencies
    sudo yum groupinstall -y "Development tools"
    sudo yum install -y pdfjam python-devel libxml2 libxslt libxml2-devel libxslt-devel libyaml-devel lxml python-lxml libdbi-dbd-sqlite zlib-devel xz-devel zlib-dev ncurses-devel bzip2-devel openssl-devel libpcap-devel readline-devel python-sqlite2 tk-devel gdbm-devel db4-devel sqlite-devel
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
    sudo pip install virtualenv    
    cd ; virtualenv -p python2.7 $ENV_DIR
    activate_python_virtualenv
    pip install --upgrade pip
    mkdir checkouts ; cd checkouts
    git clone https://github.com/rtfd/readthedocs.org.git
    cd readthedocs.org
    echo 'Installing rtd reqs'
    pip install -r pip_requirements.txt
    pip install sphinx_bootstrap_theme --upgrade
    pip install sphinx --upgrade
    pip install pygments --upgrade
    pip install gunicorn --upgrade
    pip install django-redis-cache --upgrade
    echo 'Done installing rtd reqs'
    cd $RTD_DIR
    # Lets add a pause until the users agrees to continue
    while true
    do
	read -p "Continue to manage rtd? (type Yes)..." input </dev/tty
	case $input in
	    [Yes]* )
		echo "Great, continue."
		break;;
	    * )
		echo "Enter Yes, please."
		;;
	esac
    done
    echo 'manage.py syncdb...'
    $ENV_PYTHON_BIN manage.py syncdb
    echo 'manage.py migrate...'
    $ENV_PYTHON_BIN manage.py migrate
    echo 'manage.py test...'
    $ENV_PYTHON_BIN manage.py test
    install_configure_nginx
    echo 'Configuring /etc/hosts with rtd'
    [ `grep "read-the-docs" /etc/hosts | wc -l` -gt 0 ] && echo 'read-the-docs already in /etc/hosts' || sudo sh -c 'echo "127.0.0.1   read-the-docs.localhost" >> /etc/hosts'
    echo 'Done installing rtd'
}
# =================================================

# -------------------------------------------------
do_install () {
    # No iptables, please
    sudo service iptables stop
    sudo chkconfig iptables off    
    # Installing requirements
    install_req    
    # Installing python2.7 if needed
    install_python27
    # Installing rtd from Python sources
    install_rtd_core
}
# -------------------------------------------------

# -------------------------------------------------
do_run_dev () {
    activate_python_virtualenv
    cd $RTD_DIR
    echo 'Running rtd server!'
    $ENV_PYTHON_BIN manage.py runserver 0.0.0.0:8000
}
# -------------------------------------------------

# -------------------------------------------------
do_run_gunicorn () {
    activate_python_virtualenv
    cd $RTD_DIR
    echo 'Running rtd server with gunicorn!'
    export PYTHONPATH=$RTD_DIR':'$RTD_IN_DIR
    export DJANGO_SETTINGS_MODULE='readthedocs.settings.sqlite'
    gunicorn readthedocs.wsgi:application --debug -w 100
}
# -------------------------------------------------

# =================================================
# Main
START=`date +%s%N`
case $1 in
    install)
	do_install
	;;
    run-dev)
	do_run_dev
	;;
    run-gunicorn)
	do_run_gunicorn
	;;
    *)
	qquit
	;;
esac
END=`date +%s%N`
ELAPSED=`echo "scale=8; ($END - $START) / 1000000000" | bc`
echo 'Elapsed time:'$ELAPSED
# =================================================