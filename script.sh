#!/bin/bash

TMP_FOLDER=$(mktemp -d)
CONFIG_FILE='tet.conf'
CONFIGFOLDER='/root/.tet'
COIN_DAEMON='tetd'
COIN_CLI='tet-cli'
COIN_PATH='/usr/local/bin/'
COIN_REPO='https://github.com/tetra/tetra.git'
COIN_TGZ='https://github.com/tetra/tetra/releases/download/v1.0.0/Linux.zip'
COIN_ZIP=$(echo $COIN_TGZ | awk -F'/' '{print $NF}')

COIN_NAME='Tet'
COIN_PORT=2288
RPC_PORT=2289
NODEIP=$(curl -s4 icanhazip.com)

BLUE="\033[0;34m"
YELLOW="\033[0;33m"
CYAN="\033[0;36m" 
PURPLE="\033[0;35m"
RED='\033[0;31m'
GREEN="\033[0;32m"
NC='\033[0m'
MAG='\e[1;35m'

purgeOldInstallation() {
    echo -e "${GREEN}Searching and removing old $COIN_NAME files and configurations${NC}"
    systemctl stop $COIN_NAME.service > /dev/null 2>&1
    sudo killall $COIN_DAEMON > /dev/null 2>&1
	OLDKEY=$(awk -F'=' '/masternodeprivkey/ {print $2}' $CONFIGFOLDER/$CONFIG_FILE 2> /dev/null)
	if [ "$?" -eq "0" ]; then
    		echo -e "${CYAN}Saving Old Installation Genkey${NC}"
		echo -e $OLDKEY
	fi
    sudo ufw delete allow $COIN_PORT/tcp > /dev/null 2>&1
    rm rm -- "$0" > /dev/null 2>&1
    sudo rm -rf $CONFIGFOLDER > /dev/null 2>&1
    sudo rm -rf /usr/local/bin/$COIN_CLI /usr/local/bin/$COIN_DAEMON> /dev/null 2>&1
    sudo rm -rf /usr/bin/$COIN_CLI /usr/bin/$COIN_DAEMON > /dev/null 2>&1
    sudo rm -rf /tmp/*
    echo -e "${GREEN}* Done${NONE}";
}

checks() {
if [ -n "$(pidof $COIN_DAEMON)" ] || [ -e "$COIN_DAEMOM" ] ; then
  echo -e "${RED}$COIN_NAME is already installed.${NC}"
  exit 1
fi
}

prepare_system() {
echo -e "Preparing the VPS to setup. ${CYAN}$COIN_NAME${NC} ${RED}Masternode${NC}"
apt-get update >/dev/null 2>&1
DEBIAN_FRONTEND=noninteractive apt-get update > /dev/null 2>&1
DEBIAN_FRONTEND=noninteractive apt-get -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" -y -qq upgrade >/dev/null 2>&1
apt-get install -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" zip unzip >/dev/null 2>&1
if [ "$?" -gt "0" ];
  then
    echo -e "${RED}Not all required packages were installed properly. Try to install them manually by running the following commands:${NC}\n"
    echo "apt-get update"
    echo "apt install -y zip unzip"
 exit 1
fi
clear
}

download_node() {
  echo -e "${GREEN}Downloading and Installing VPS $COIN_NAME Daemon${NC}"
  cd $TMP_FOLDER >/dev/null 2>&1
  wget -q $COIN_TGZ
  unzip $COIN_ZIP >/dev/null 2>&1
  chmod +x Linux/bin/$COIN_DAEMON Linux/bin/$COIN_CLI
  cp Linux/bin/$COIN_DAEMON Linux/bin/$COIN_CLI $COIN_PATH
  cd ~ >/dev/null 2>&1
  rm -rf $TMP_FOLDER >/dev/null 2>&1
  clear
}

get_ip() {
  declare -a NODE_IPS
  for ips in $(netstat -i | awk '!/Kernel|Iface|lo/ {print $1," "}')
  do
    NODE_IPS+=$(curl --interface $ips --connect-timeout 2 -s4 icanhazip.com)
  done

  if [ ${#NODE_IPS[@]} -gt 1 ]
    then
      echo -e "${GREEN}More than one IP. Please type 0 to use the first IP, 1 for the second and so on...${NC}"
      INDEX=0
      for ip in "${NODE_IPS[@]}"
      do
        echo ${INDEX} $ip
        let INDEX=${INDEX}+1
      done
      read -e choose_ip
      NODEIP=${NODE_IPS[$choose_ip]}
  else
    NODEIP=${NODE_IPS[0]}
  fi
}

create_config() {
  mkdir $CONFIGFOLDER >/dev/null 2>&1
  RPCUSER=$(tr -cd '[:alnum:]' < /dev/urandom | fold -w10 | head -n1)
  RPCPASSWORD=$(tr -cd '[:alnum:]' < /dev/urandom | fold -w22 | head -n1)
  echo rpcuser=$RPCUSER > $CONFIGFOLDER/$CONFIG_FILE
  echo rpcpassword=$RPCPASSWORD >> $CONFIGFOLDER/$CONFIG_FILE
  echo rpcport=$RPC_PORT >> $CONFIGFOLDER/$CONFIG_FILE
  echo rpcallowip=127.0.0.1 >> $CONFIGFOLDER/$CONFIG_FILE
  echo listen=1 >> $CONFIGFOLDER/$CONFIG_FILE
  echo server=1 >> $CONFIGFOLDER/$CONFIG_FILE
  echo daemon=1 >> $CONFIGFOLDER/$CONFIG_FILE
  echo port=$COIN_PORT >> $CONFIGFOLDER/$CONFIG_FILE

}

create_key() {
  echo -e "${YELLOW}Enter your ${RED}$COIN_NAME Masternode GEN Key${NC}."
  read -e COINKEY
  if [[ -z "$COINKEY" ]]; then
  $COIN_PATH$COIN_DAEMON -daemon
  sleep 30
  if [ -z "$(ps axo cmd:100 | grep $COIN_DAEMON)" ]; then
   echo -e "${RED}$COIN_NAME server couldn not start. Check /var/log/syslog for errors.{$NC}"
   exit 1
  fi
  COINKEY=$($COIN_PATH$COIN_CLI masternode genkey)
  if [ "$?" -gt "0" ];
    then
    echo -e "${RED}Wallet not fully loaded. Let us wait and try again to generate the GEN Key${NC}"
    sleep 30
    COINKEY=$($COIN_PATH$COIN_CLI masternode genkey)
  fi
  $COIN_PATH$COIN_CLI stop
fi
clear
}

update_config() {
  sed -i 's/daemon=1/daemon=0/' $CONFIGFOLDER/$CONFIG_FILE
  echo  "" >> $CONFIGFOLDER/$CONFIG_FILE 
  echo logintimestamps=1 >> $CONFIGFOLDER/$CONFIG_FILE
  echo maxconnections=256 >> $CONFIGFOLDER/$CONFIG_FILE
  echo  "" >> $CONFIGFOLDER/$CONFIG_FILE
  echo masternode=1 >> $CONFIGFOLDER/$CONFIG_FILE
  echo masternodeaddr=$NODEIP:$COIN_PORT >> $CONFIGFOLDER/$CONFIG_FILE
  echo masternodeprivkey=$COINKEY >> $CONFIGFOLDER/$CONFIG_FILE
  echo  "" >> $CONFIGFOLDER/$CONFIG_FILE
  echo addnode=104.248.159.84 >> $CONFIGFOLDER/$CONFIG_FILE
  echo addnode=104.248.116.47 >> $CONFIGFOLDER/$CONFIG_FILE
  echo addnode=142.93.32.240 >> $CONFIGFOLDER/$CONFIG_FILE
  echo addnode=178.128.226.95 >> $CONFIGFOLDER/$CONFIG_FILE
  echo addnode=142.93.162.83 >> $CONFIGFOLDER/$CONFIG_FILE

}

configure_systemd() {
  cat << EOF > /etc/systemd/system/$COIN_NAME.service
[Unit]
Description=$COIN_NAME service
After=network.target

[Service]
User=root
Group=root

Type=forking
#PIDFile=$CONFIGFOLDER/$COIN_NAME.pid

ExecStart=$COIN_PATH$COIN_DAEMON -daemon -conf=$CONFIGFOLDER/$CONFIG_FILE -datadir=$CONFIGFOLDER
ExecStop=-$COIN_PATH$COIN_CLI -conf=$CONFIGFOLDER/$CONFIG_FILE -datadir=$CONFIGFOLDER stop

Restart=always
PrivateTmp=true
TimeoutStopSec=60s
TimeoutStartSec=10s
StartLimitInterval=120s
StartLimitBurst=5

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  sleep 3
  systemctl start $COIN_NAME.service
  systemctl enable $COIN_NAME.service >/dev/null 2>&1

  if [[ -z "$(ps axo cmd:100 | egrep $COIN_DAEMON)" ]]; then
    echo -e "${RED}$COIN_NAME is not running${NC}, please investigate. You should start by running the following commands as root:"
    echo -e "${GREEN}systemctl start $COIN_NAME.service"
    echo -e "systemctl status $COIN_NAME.service"
    echo -e "less /var/log/syslog${NC}"
    exit 1
  fi
}

setup_node() {
  get_ip
  create_config
  create_key
  update_config
  configure_systemd
}


##### Main #####
clear
purgeOldInstallation
checks
prepare_system
download_node
setup_node

