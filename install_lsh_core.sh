#!/bin/bash

DBpassword="password"
RED='\033[0;31m'
YELLOW='\033[0;33m'
GREEN='\033[0;32m'
NC='\033[0m'


run_install_u18 ()
{
        read -p "Do you want to install missing packages ($1)? [Y/n]: " answer
                answer=${answer:N}
        [[ $answer =~ [Yy] && $1 = "nodejs" ]] && /usr/bin/curl -sL https://deb.nodesource.com/setup_10.x | sudo -E bash - && sudo apt-get install -qqy nodejs
                [[ $answer =~ [Yy] ]] && sudo apt-get install -qqy $1
}

run_install_u16 ()
{
        read -p "Do you want to install missing packages ($1)? [Y/n]: " answer
                answer=${answer:N}
        [[ $answer =~ [Yy] && $1 = "nodejs" ]] && /usr/bin/curl -sL https://deb.nodesource.com/setup_10.x | sudo -E bash - && sudo apt-get install -qqy nodejs
                [[ $answer =~ [Yy] && $1 = "postgresql-10" ]] && wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add - && sudo sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt/ $(lsb_release -sc)-pgdg main" > /etc/apt/sources.list.d/PostgreSQL.list' && sudo apt-get -qqy update && sudo apt-get -qqy install postgresql-10
                [[ $answer =~ [Yy] ]] && sudo apt-get install -qqy $1
}


echo -e "${GREEN} \nTrying to install missing packages:\n ${NC}"
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




prepare_db ()
{

        echo -e "${GREEN} \nRunning Postgres database steps!\n ${NC}"

                if sudo -Hiu postgres psql -lqt | cut -d \| -f 1 | grep -qw 'lisk_test\|leasehold_test'; then
                        echo -e "${YELLOW} \nSome databases already exist! You can see existing databases with: sudo -Hiu postgres psql -lqt\n ${NC}"
                else
                        
                        sudo -u postgres -i createuser --createdb leasehold
                        sudo -u postgres -i createdb lisk_test --owner leasehold
                        sudo -u postgres -i createdb leasehold_test --owner leasehold
                        sudo -Hiu postgres psql -d lisk_test -c "alter user leasehold with password '$DBpassword';"
                        echo -e "${GREEN}Done!\n ${NC}"
                                fi

}


install_lsh_core ()
{

        if [ `whoami` = 'leasehold' ] && [ ! -d ~/leasehold-core ];then
                echo -e "${GREEN} \nInstalling Leasehold packages:\n ${NC}"
                        cd ~
                        /usr/bin/git clone https://github.com/Leasehold/leasehold-core.git
                        cd ~/leasehold-core
                        sudo /usr/bin/npm install --no-progress
                        sudo /usr/bin/npm install --no-progress pm2 -g
                        echo -e "${GREEN}Done!\n ${NC}"
        else
                echo -e "${YELLOW} \nYou have to run this script as user \"leasehold\" and folder \"leasehold-core\" should not exist in home directory!\n ${NC}"
                        exit 0
                        fi

}


start_lsh ()
{
        if [ `whoami` = 'leasehold' ] && [ -f ~/leasehold-core/index.js ];then
                echo -e "${GREEN} \nStarting process with \"pm2\"\n ${NC}"
                        if ! /usr/bin/pm2 list | grep -w "leasehold-core"; then
                                cd ~/leasehold-core
                                pm2 start index.js --name "leasehold-core"
                                echo -e "${GREEN}Done!\n ${NC}"
                        else
                                echo -e "${RED} \nThere is already a process \"leasehold-core\" in pm2 ! Delete it before running again (pm2 delete leasehold-core)\n ${NC}"
                                        exit 0
                        fi
        else
                echo -e "${YELLOW} \nYou have to run this script as user \"leasehold\" and folder \"leasehold-core\" SHOULD exist in home directory!\n ${NC}"
        fi
}


prepare_db
install_lsh_core
start_lsh
echo -e "${GREEN} \nAll steps are done! You can verify if the process is running by \"pm2 list\" and accessing endpoint via <ip>:7010/api/node/status\n ${NC}"
