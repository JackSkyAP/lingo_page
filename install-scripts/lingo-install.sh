#!/bin/bash -ex

# This lingo-bbb-patch.sh script automates many of the installation and configuration
# steps at
#    https://www.click-ap.com/bbb/lingo
#
#  Examples
#

usage() {
    set +x
    cat 1>&2 <<HERE
USAGE:
    wget -qO- https://johnclickap.github.io/lingo_page/lingo-install.sh | bash -s -- [OPTIONS]

OPTIONS (install Lingo):
  -v <version>           Install given version of BigBlueButton (e.g. 'xenial-220') (required)
  -s <hostname>          Configure server with <hostname>
  -e <email>             Email for Let's Encrypt certbot
  -m <link_path>         Create a Symbolic link from /var/bigbluebutton to <link_path> 
  -p <host>              Use apt-get proxy at <host>
  -r <host>              Use alternative apt repository (such as packages-eu.bigbluebutton.org)
  -h                     Print help

SUPPORT:
    Community: https://www.click-ap.com/lingo
         Docs: https://github.com/clickap/bbb22-install

HERE
}

main() {
  export DEBIAN_FRONTEND=noninteractive
  PACKAGE_REPOSITORY=ubuntu.bigbluebutton.org

  need_x64

  while builtin getopts "hs:r:v:e:p:m" opt "${@}"; do

    case $opt in
      h)
        usage
        exit 0
        ;;

      s)
        HOST=$OPTARG
        if [ "$HOST" == "bbb.click-ap.com" ]; then 
          err "You must specify a valid hostname (not the hostname given in the docs)."
        fi
        check_host $HOST
        ;;
      r)
        PACKAGE_REPOSITORY=$OPTARG
        ;;
      e)
        EMAIL=$OPTARG
        if [ "$EMAIL" == "info@example.com" ]; then 
          err "You must specify a valid email address (not the email in the docs)."
        fi
        ;;
      v)
        VERSION=$OPTARG
        check_version $VERSION
        ;;
      p)
        PROXY=$OPTARG
        ;;

      m)
        LINK_PATH=$OPTARG
        ;;

      :)
        err "Missing option argument for -$OPTARG"
        exit 1
        ;;

      \?)
        err "Invalid option: -$OPTARG" >&2
        usage
        ;;
    esac
  done

  check_apache2

  if [ ! -z "$PROXY" ]; then
    echo "Acquire::http::Proxy \"http://$PROXY:3142\";"  > /etc/apt/apt.conf.d/01proxy
  fi

  if [ -z "$VERSION" ]; then
    usage
    exit 0
  fi

  # We're installing BigBlueButton
  env
  if [ "$DISTRO" == "xenial" ]; then 
    check_ubuntu 16.04
    TOMCAT_USER=tomcat7
  fi
  if [ "$DISTRO" == "bionic" ]; then 
    check_ubuntu 18.04
    TOMCAT_USER=tomcat8
  fi
  check_mem

  get_IP

  echo ttf-mscorefonts-installer msttcorefonts/accepted-mscorefonts-eula select true | debconf-set-selections

  need_pkg curl

  if [ "$DISTRO" == "xenial" ]; then 
    rm -rf /etc/apt/sources.list.d/jonathonf-ubuntu-ffmpeg-4-xenial.list 
    need_ppa bigbluebutton-ubuntu-support-xenial.list ppa:bigbluebutton/support E95B94BC # Latest version of ffmpeg
    need_ppa rmescandon-ubuntu-yq-xenial.list ppa:rmescandon/yq                 CC86BB64 # Edit yaml files with yq
    apt-get -y -o DPkg::options::="--force-confdef" -o DPkg::options::="--force-confold" install grub-pc update-notifier-common

    # Remove default version of nodejs for Ubuntu 16.04 if installed
    if dpkg -s nodejs | grep Version | grep -q 4.2.6; then
      apt-get purge -y nodejs > /dev/null 2>&1
    fi
    apt-get purge -yq kms-core-6.0 kms-elements-6.0 kurento-media-server-6.0 > /dev/null 2>&1  # Remove older packages

    if [ ! -f /etc/apt/sources.list.d/nodesource.list ]; then
      curl -sL https://deb.nodesource.com/setup_8.x | sudo -E bash -
    fi
    if ! apt-cache madison nodejs | grep -q node_8; then
      err "Did not detect nodejs 8.x candidate for installation"
    fi
    
    if ! apt-key list A15703C6 | grep -q A15703C6; then
      wget -qO - https://www.mongodb.org/static/pgp/server-3.4.asc | sudo apt-key add -
    fi
    if apt-key list A15703C6 | grep -q expired; then 
      wget -qO - https://www.mongodb.org/static/pgp/server-3.4.asc | sudo apt-key add -
    fi
    rm -rf /etc/apt/sources.list.d/mongodb-org-4.0.list
    echo "deb http://repo.mongodb.org/apt/ubuntu xenial/mongodb-org/3.4 multiverse" | sudo tee /etc/apt/sources.list.d/mongodb-org-3.4.list
    MONGODB=mongodb-org
    
    need_pkg openjdk-8-jre
  fi

  apt-get update
  apt-get dist-upgrade -yq

  need_pkg nodejs $MONGODB apt-transport-https haveged build-essential yq # default-jre
  need_pkg bigbluebutton

  # 檢查 lxc nat for FreeSwitch
  check_lxc
  check_nat
  check_LimitNOFILE

  if [ ! -z "$LINK_PATH" ]; then
    ln -s "$LINK_PATH" "/var/bigbluebutton"
  fi

  apt-get auto-remove -y

  if ! systemctl show-environment | grep LANG= | grep -q UTF-8; then
    sudo systemctl set-environment LANG=C.UTF-8
  fi

}

say() {
  echo "lingo-install: $1"
}

err() {
  say "$1" >&2
  exit 1
}

check_root() {
  if [ $EUID != 0 ]; then err "You must run this command as root."; fi
}

check_mem() {
  MEM=`grep MemTotal /proc/meminfo | awk '{print $2}'`
  MEM=$((MEM/1000))
  if (( $MEM < 3940 )); then err "Your server needs to have (at least) 4G of memory."; fi
}

check_ubuntu(){
  RELEASE=$(lsb_release -r | sed 's/^[^0-9]*//g')
  if [ "$RELEASE" != $1 ]; then err "You must run this command on Ubuntu $1 server."; fi
}

need_x64() {
  UNAME=`uname -m`
  if [ "$UNAME" != "x86_64" ]; then err "You must run this command on a 64-bit server."; fi
}

get_IP() {
  if [ ! -z "$IP" ]; then return 0; fi

  # Determine local IP
  if LANG=c ifconfig | grep -q 'venet0:0'; then
    IP=$(ifconfig | grep -v '127.0.0.1' | grep -E "[0-9]*\.[0-9]*\.[0-9]*\.[0-9]*" | tail -1 | cut -d: -f2 | awk '{ print $1}')
  else
    IP=$(hostname -I | cut -f1 -d' ')
  fi

  # Determine external IP 
  if [ -r /sys/devices/virtual/dmi/id/product_uuid ] && [ `head -c 3 /sys/devices/virtual/dmi/id/product_uuid` == "EC2" ]; then
    # Ec2
    local external_ip=$(wget -qO- http://169.254.169.254/latest/meta-data/public-ipv4)
  elif [ -f /var/lib/dhcp/dhclient.eth0.leases ] && grep -q unknown-245 /var/lib/dhcp/dhclient.eth0.leases; then
    # Azure
    local external_ip=$(curl -H Metadata:true "http://169.254.169.254/metadata/instance/network/interface/0/ipv4/ipAddress/0/publicIpAddress?api-version=2017-08-01&format=text")
  elif [ -f /run/scw-metadata.cache ]; then
    # Scaleway
    local external_ip=$(grep "PUBLIC_IP_ADDRESS" /run/scw-metadata.cache | cut -d '=' -f 2)
  elif which dmidecode > /dev/null && dmidecode -s bios-vendor | grep -q Google; then
    # Google Compute Cloud
    local external_ip=$(wget -O - -q "http://metadata/computeMetadata/v1/instance/network-interfaces/0/access-configs/0/external-ip" --header 'Metadata-Flavor: Google')
  elif [ ! -z "$1" ]; then
    # Try and determine the external IP from the given hostname
    need_pkg dnsutils
    local external_ip=$(dig +short $1 @resolver1.opendns.com | grep '^[.0-9]*$' | tail -n1)
  fi

  # Check if the external IP reaches the internal IP
  if [ ! -z "$external_ip" ] && [ "$IP" != "$external_ip" ]; then
    if which nginx; then
      systemctl stop nginx
    fi

    need_pkg netcat-openbsd
    nc -l -p 443 > /dev/null 2>&1 &
    nc_PID=$!
    
     # Check if we can reach the server through it's external IP address
     if nc -zvw3 $external_ip 443  > /dev/null 2>&1; then
       INTERNAL_IP=$IP
       IP=$external_ip
     fi

    kill $nc_PID  > /dev/null 2>&1;

    if which nginx; then
      systemctl start nginx
    fi
  fi

  if [ -z "$IP" ]; then err "Unable to determine local IP address."; fi
}

need_pkg() {
  check_root

  if ! dpkg -s ${@:1} >/dev/null 2>&1; then
    LC_CTYPE=C.UTF-8 apt-get install -yq ${@:1}
  fi
}

need_ppa() {
  need_pkg software-properties-common
  if [ ! -f /etc/apt/sources.list.d/$1 ]; then
    LC_CTYPE=C.UTF-8 add-apt-repository -y $2 
  fi
  if ! apt-key list $3 | grep -q -E "1024|4096"; then  # Let's try it a second time
    LC_CTYPE=C.UTF-8 add-apt-repository $2 -y
    if ! apt-key list $3 | grep -q -E "1024|4096"; then
      err "Unable to setup PPA for $2"
    fi
  fi
}

check_version() {
  if ! echo $1 | egrep -q "xenial|bionic"; then err "This script can only install BigBlueButton 2.0 (or later)"; fi
  DISTRO=$(echo $1 | sed 's/-.*//g')
  if ! wget -qS --spider "https://$PACKAGE_REPOSITORY/$1/dists/bigbluebutton-$DISTRO/Release.gpg" > /dev/null 2>&1; then
    err "Unable to locate packages for $1 at $PACKAGE_REPOSITORY."
  fi
  check_root
  need_pkg apt-transport-https
  if ! apt-key list | grep -q "BigBlueButton apt-get"; then
    wget https://$PACKAGE_REPOSITORY/repo/bigbluebutton.asc -O- | apt-key add -
  fi

  # Check if were upgrading from 2.0 (the ownership of /etc/bigbluebutton/nginx/web has changed from bbb-client to bbb-web)
  if [ -f /etc/apt/sources.list.d/bigbluebutton.list ]; then
    if grep -q xenial-200 /etc/apt/sources.list.d/bigbluebutton.list; then
      if echo $VERSION | grep -q xenial-220; then
        if dpkg -l | grep -q bbb-client; then
          apt-get purge -y bbb-client
        fi
      fi
    fi
  fi

  echo "deb https://$PACKAGE_REPOSITORY/$VERSION bigbluebutton-$DISTRO main" > /etc/apt/sources.list.d/bigbluebutton.list
}

check_host() {
  if [ -z "$PROVIDED_CERTIFICATE" ]; then
    need_pkg dnsutils apt-transport-https net-tools
    DIG_IP=$(dig +short $1 | grep '^[.0-9]*$' | tail -n1)
    if [ -z "$DIG_IP" ]; then err "Unable to resolve $1 to an IP address using DNS lookup.";  fi
    get_IP $1
    if [ "$DIG_IP" != "$IP" ]; then err "DNS lookup for $1 resolved to $DIG_IP but didn't match local $IP."; fi
  fi
}

check_apache2() {
  if dpkg -l | grep -q apache2-bin; then err "You must unisntall the Apache2 server first"; fi
}

# If running under LXC, prepare LXC service
check_lxc() {
  if grep -qa container=lxc /proc/1/environ; then
    # codeholder 
    echo "check_lxe()"
  fi
}

# Check if running externally with internal/external IP addresses
check_nat() {
  if [ ! -z "$INTERNAL_IP" ]; then
    echo "ip addr add $IP dev lo"
    #ip addr add $IP dev lo

    # If dummy NIC is not in dummy-nic.service (or the file does not exist), update/create it
    echo "dummy NIC"
  fi
}

check_LimitNOFILE() {
  CPU=$(nproc --all)

  if [ "$CPU" -gt 36 ]; then
    if [ -f /lib/systemd/system/bbb-web.service ]; then
      # Let's create an override file to increase the number of LimitNOFILE 
      mkdir -p /etc/systemd/system/bbb-web.service.d/
      cat > /etc/systemd/system/bbb-web.service.d/override.conf << HERE
[Service]
LimitNOFILE=
LimitNOFILE=8192
HERE
      systemctl daemon-reload
    fi
  fi
}

main "$@" || exit 1
