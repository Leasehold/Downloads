#!/bin/bash

DB_PASSWORD="password"

RED='\033[0;31m'
YELLOW='\033[0;33m'
GREEN='\033[0;32m'
NC='\033[0m'
IP=`/sbin/ifconfig -a | grep -A1 "eth0" | tail -1 | awk '{print $2}' | cut -d":" -f2`


while getopts :n:t: option
        do
                case "${option}"
                in
                n) NETWORK=${OPTARG};;
				t) TYPE=${OPTARG};;
                esac
        done


if [[ "$NETWORK" != "mainnet" && "$NETWORK" != "testnet" ]];then
		echo -e "${RED} \nYou did not specify the network using -n flag (-n mainnet/testnet)\n ${NC}"
		exit 1
fi


if [[ `whoami` != 'leasehold' || -d ~/leasehold-core-$NETWORK ]];then
		echo -e "${YELLOW} \nYou have to run this script as user \"leasehold\" and folder \"leasehold-core-$NETWORK\" should not exist in home directory!\n ${NC}"
		exit 1
fi


if [[ ! -z $TYPE && $TYPE == dex ]];then
		echo -e "${GREEN} \nCollecting DEX info! \n ${NC}"
		read -p "Enter the shared Lisk wallet address to be used in config file: " lskWallet
		read -p "Enter the shared Leasehold wallet address to be used in config file: " lshWallet
		read -p "Enter the Lisk sharedPassphrase: " lskSharedPassphrase
		read -p "Enter the Leasehold sharedPassphrase: " lshSharedPassphrase
		read -p "Enter your PERSONAL Lisk passphrase: " lskPassphrase
		read -p "Enter your PERSONAL Leasehold passphrase: " lshPassphrase
		echo -e "${GREEN}Done!\n ${NC}"
fi

[[ "$NETWORK" == "mainnet" ]] && PORT="8010" || PORT="7010"
[[ "$NETWORK" == "mainnet" ]] && LSH_SNAPSHOT="leasehold_main_backup_13072020.gz" || LSH_SNAPSHOT="leasehold_test_backup_26032020.gz"
[[ "$NETWORK" == "mainnet" ]] && LSK_SNAPSHOT="lisk_main_backup-13068186.gz" || LSK_SNAPSHOT="lisk_test_backup-11369133.gz"
[[ "$NETWORK" == "mainnet" ]] && { LSH_DB="leasehold_main"; LSK_DB="lisk_main"; } || { LSH_DB="leasehold_test"; LSK_DB="lisk_test"; }
DEX_SNAPSHOT_FILE="https://raw.githubusercontent.com/Leasehold/Downloads/master/dex-snapshots/$NETWORK/dex-snapshot-lsh-lsk.json"


run_install_u18 ()
{
        [[ $1 = "nodejs" ]] && /usr/bin/curl -sL https://deb.nodesource.com/setup_10.x | sudo -E bash - && sudo apt-get install -qqy nodejs
        sudo apt-get install -qqy $1
}

run_install_u16 ()
{
        [[ $1 = "nodejs" ]] && /usr/bin/curl -sL https://deb.nodesource.com/setup_10.x | sudo -E bash - && sudo apt-get install -qqy nodejs
        [[ $1 = "postgresql-10" ]] && wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add - && sudo sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt/ $(lsb_release -sc)-pgdg main" > /etc/apt/sources.list.d/PostgreSQL.list' && sudo apt-get -qqy update && sudo apt-get -qqy install postgresql-10
        sudo apt-get install -qqy $1
}


echo -e "${GREEN} \nInstalling missing packages:\n ${NC}"
packages="git nodejs postgresql-10 curl wget build-essential"

for pack in $packages; do
        if grep -sq "18." /etc/lsb-release; then
                dpkg -s $pack >/dev/null 2>&1 || run_install_u18 $pack
        elif grep -sq "16." /etc/lsb-release; then
                dpkg -s $pack >/dev/null 2>&1 || run_install_u16 $pack
        else
                echo -e "${YELLOW} \nThis is not a supported distro!\n ${NC}"
                exit 1
        fi
done

echo -e "${GREEN}Done!\n ${NC}"



load_lsk_snapshot ()
{
	echo -e "${GREEN} \nUploading LSK snapshots to DB!\n ${NC}"
	wget http://snapshots.lisk.io.s3-eu-west-1.amazonaws.com/lisk/$NETWORK/$LSK_SNAPSHOT
	gzip --decompress --to-stdout ./$LSK_SNAPSHOT | psql $LSK_DB -U leasehold
	rm -f ./$LSK_SNAPSHOT
	echo -e "${GREEN}Done!\n ${NC}"
}


load_lsh_snapshot ()
{
	echo -e "${GREEN} \nUploading LSH snapshots to DB!\n ${NC}"
	wget --no-check-certificate https://testnet.leasehold.io/snapshots/$NETWORK/$LSH_SNAPSHOT
	gzip --decompress --to-stdout ./$LSH_SNAPSHOT | psql $LSH_DB -U leasehold
	rm -f ./$LSH_SNAPSHOT
	echo -e "${GREEN}Done!\n ${NC}"
}


prepare_db ()
{

        echo -e "${GREEN} \nRunning Postgres database steps!\n ${NC}"

                if sudo -Hiu postgres psql -lqt | cut -d \| -f 1 | grep -qw '$LSK_DB\|$LSH_DB'; then
                        echo -e "${YELLOW} \nSome databases already exist! Dropping them!\n ${NC}"
                        sudo -u postgres -i dropdb $LSK_DB
			sudo -u postgres -i dropdb $LSH_DB
                else
                        sudo sed -i 's/max_connections = 100/max_connections = 300/g' /etc/postgresql/10/main/postgresql.conf
                        sudo sed -i 's/shared_buffers = 128MB/shared_buffers = 256MB/g' /etc/postgresql/10/main/postgresql.conf
                        sudo systemctl restart postgresql.service
                        sudo -u postgres -i createuser --createdb leasehold
                        sudo -u postgres -i createdb $LSK_DB --owner leasehold
                        sudo -u postgres -i createdb $LSH_DB --owner leasehold
                        sudo -Hiu postgres psql -d $LSK_DB -c "alter user leasehold with password '$DB_PASSWORD';"
                        sudo -Hiu postgres psql -d $LSK_DB -c "alter role leasehold superuser;"
                        echo -e "${GREEN}Done!\n ${NC}"
                        
                        load_lsk_snapshot
                        load_lsh_snapshot 
                fi

}


install_lsh_core ()
{

        if [ `whoami` = 'leasehold' ] && [ ! -d ~/leasehold-core-$NETWORK ];then
                echo -e "${GREEN} \nInstalling Leasehold packages:\n ${NC}"
                        cd ~
                        /usr/bin/git clone https://github.com/Leasehold/leasehold-core.git leasehold-core-$NETWORK
                        cd ~/leasehold-core-$NETWORK
                        [[ "$NETWORK" == "testnet" ]] && wget -qN "https://raw.githubusercontent.com/Leasehold/Downloads/master/configs/testnet/config.json"
			sudo /usr/bin/npm install --no-progress
                        sudo /usr/bin/npm install --no-progress pm2 -g
                        echo -e "${GREEN}Done!\n ${NC}"
        else
                echo -e "${YELLOW} \nYou have to run this script as user \"leasehold\" and folder \"leasehold-core-$NETWORK\" should exist in home directory!\n ${NC}"
                        exit 0
                        fi

}


start_lsh ()
{
        if [ `whoami` = 'leasehold' ] && [ -f ~/leasehold-core-$NETWORK/index.js ];then
                echo -e "${GREEN} \nStarting process with \"pm2\"\n ${NC}"
                        if ! /usr/bin/pm2 list | grep -w "leasehold-core-$NETWORK"; then
                                cd ~/leasehold-core-$NETWORK
                                pm2 start index.js --name "leasehold-core-$NETWORK" -o "/dev/null" -e "/dev/null"
                                echo -e "${GREEN}Done!\n ${NC}"
                        else
                                echo -e "${RED} \nThere is already a process \"leasehold-core-$NETWORK\" in pm2! Delete it before running again (pm2 delete leasehold-core-$NETWORK)\n ${NC}"
                                        exit 0
                        fi
        else
                echo -e "${YELLOW} \nYou have to run this script as user \"leasehold\" and folder \"leasehold-core-$NETWORK\" should not exist in home directory!\n ${NC}"
        fi
}


configure_dex()
{
        echo -e "${GREEN} \nUpdating DEX config! \n ${NC}"
        cd ~/leasehold-core-$NETWORK && wget -q "$DEX_SNAPSHOT_FILE"
        sed -i 's/"moduleEnabled":\s*false\s*,/"moduleEnabled": true,/g' ./config.json
        sed -i "/lsk/,/walletAddress/s/\"walletAddress\":\s*\"\"\s*,/\"walletAddress\": \"$lskWallet\",/" ./config.json
        sed -i "/lsh/,/walletAddress/s/\"walletAddress\":\s*\"\"\s*,/\"walletAddress\": \"$lshWallet\",/" ./config.json
        sed -i "/lsk/,/sharedPassphrase/s/\"sharedPassphrase\":\s*\"\"\s*,/\"sharedPassphrase\": \"$lskSharedPassphrase\",/" ./config.json
        sed -i "/lsh/,/sharedPassphrase/s/\"sharedPassphrase\":\s*\"\"\s*,/\"sharedPassphrase\": \"$lshSharedPassphrase\",/" ./config.json
        sed -i "/lsk/,/passphrase/s/\"passphrase\":\s*\"\"\s*,/\"passphrase\": \"$lskPassphrase\",/" ./config.json
        sed -i "/lsh/,/passphrase/s/\"passphrase\":\s*\"\"\s*,/\"passphrase\": \"$lshPassphrase\",/" ./config.json

        echo -e "${GREEN}Done!\n ${NC}"
}


prepare_db
install_lsh_core

if [[ ! -z $TYPE && $TYPE == dex ]];then
        configure_dex
fi

start_lsh

echo -e "${GREEN} \nAll steps are done! You can verify if the process is running by \"pm2 list\" and accessing endpoint: http://$IP:$PORT/api/node/status\n ${NC}"
