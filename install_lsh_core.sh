#!/bin/bash

DBpassword="password"
RED='\033[0;31m'
YELLOW='\033[0;33m'
GREEN='\033[0;32m'
NC='\033[0m'


run_install ()
{
        read -p "Do you want to install missing packages ($1)? [Y/n]: " answer
        answer=${answer:N}
        [[ $answer =~ [Yy] && $1 = "nodejs" ]] && /usr/bin/curl -sL https://deb.nodesource.com/setup_10.x | sudo -E bash - && sudo apt-get install -qqy nodejs
        [[ $answer =~ [Yy] ]] && sudo apt-get install -qqy $1
}

packages="git nodejs postgresql-10 curl wget build-essential"

echo -e "${GREEN} \nInstalling missing packages:\n ${NC}"

for pack in $packages; do

        dpkg -s $pack >/dev/null 2>&1 || run_install $pack

done



prepare_db ()
{

        echo -e "${GREEN} \nRunning Postgres database preparation steps:\n ${NC}"

        if sudo -Hiu postgres psql -lqt | cut -d \| -f 1 | grep -qw 'lisk_test\|leasehold_test'; then
                echo -e "${YELLOW} \nSome databases already exist! You can see existing databases with: sudo -Hiu postgres psql -lqt\n ${NC}"
                #exit 0
        else
                echo -e "${GREEN} \nCreating Postgres databases\n ${NC}"
                sudo -u postgres -i createuser --createdb lisk
                sudo -u postgres -i createdb lisk_test --owner lisk
                sudo -u postgres -i createdb leasehold_test --owner lisk
                sudo -Hiu postgres psql -d lisk_test -c "alter user lisk with password '$DBpassword';"
        fi

}


install_lsh_core ()
{

        if [ `whoami` = 'leasehold' ] && [ ! -d ~/leasehold-core ];then
                echo -e "${GREEN} \nInstalling Leasehold packages:\n ${NC}"
                cd ~
                /usr/bin/git clone https://github.com/Leasehold/leasehold-core.git
                cd ~/leasehold-core
                sudo /usr/bin/npm install
                sudo /usr/bin/npm install pm2 -g
                echo -e "${GREEN} \nStarting process with \"pm2\"\n ${NC}"
                if ! pm2 list | grep -qw "leasehold-core"; then
                        pm2 start index.js --name "leasehold-core"
                else
                        echo -e "${RED} \nThere is already a process \"leasehold-core\" in pm2 ! Delete it before running again (pm2 delete leasehold-core)\n ${NC}"
                        exit 0
                fi
        else
                echo -e "${YELLOW} \nYou have to run this script as user \"leasehold\" and folder \"leasehold-core\" should not exist in home directory!\n ${NC}"
                exit 0
        fi

}

prepare_db
install_lsh_core
