#!/bin/bash

cluster_name="Meetup_Cluster"
node_name="Node_1"
host="['127.0.0.1', '192.168.1.17']"
ssh_port="1242"


echo "The script installs Oracle JDK and ElasticSearch."
if [[ $EUID -ne 0 ]]; then
   echo -e "\033[31m[-] This script must be run as root. \033[0m"
   exit 1
fi

function sedeasy {
  sed -i "s/$(echo $1 | sed -e 's/\([[\/.*]\|\]\)/\\&/g')/$(echo $2 | sed -e 's/[\/&]/\\&/g')/g" $3
}

echo -e "\033[32m[+] Debian Update \033[0m"
apt-get update > /dev/null

echo -e "\033[32m[+] Installation of the following packages: iptables, libpam-cracklib, fail2ban, portsentry \033[0m"
apt-get install -y iptables libpam-cracklib fail2ban portsentry > /dev/null
#apt-get dist-upgrade

echo -e "\033[32m[+] Downloading of JDK \033[0m"
COOKIE="gpw_e24=x; oraclelicense=accept-securebackup-cookie"
wget --header="Cookie: $COOKIE" http://download.oracle.com/otn-pub/java/jdk/8u25-b17/jdk-8u25-linux-x64.tar.gz

echo -e "\033[32m[+] Looking for JDK archive...\033[0m"
VERSION=`ls jdk-*-linux-*.tar.gz 2>/dev/null | awk -F '-' '{print $2}' | awk -F 'u' '{print $1}' | sort -n | tail -1`
UPDATE=`ls jdk-$VERSION*-linux-*.tar.gz 2>/dev/null | awk -F '-' '{print $2}' | awk -F 'u' '{print $2}' | sort -n | tail -1`
[ ! -z $UPDATE ] && UPDATE_SUFFIX="u$UPDATE"
LATEST_JDK_ARCHIVE=`ls jdk-$VERSION$UPDATE_SUFFIX-linux-*.tar.gz 2>/dev/null | sort | tail -1`
if [ -z "$LATEST_JDK_ARCHIVE" ] || [ -z "$VERSION" ]; then
    echo -e "\033[31m[-]Archive with JDK wasn't found. It should be in the current directory.\033[0m"
    exit 1
fi
echo -e "\033[32m[+] Found archive: $LATEST_JDK_ARCHIVE \033[0m"
echo -e "\033[32m[+] Version: $VERSION \033[0m"
[ ! -z $UPDATE ] && echo "Update: $UPDATE"

INSTALL_DIR=/usr/lib/jvm
JDK_DIR=$INSTALL_DIR/java-$VERSION-oracle

echo -e "\033[32m[+] Extracting archive... \033[0m"
tar -xzf $LATEST_JDK_ARCHIVE
if [ $? -ne 0 ]; then
    echo -e "\033[31m[-] Error while extraction archive.\033[0m"
    exit 1
fi

ARCHIVE_DIR="jdk1.$VERSION.0"
if [ ! -z $UPDATE ]; then
  ARCHIVE_DIR=$ARCHIVE_DIR"_"`printf "%02d" $UPDATE`
fi

if [ ! -d $ARCHIVE_DIR ]; then
    echo -e "\033[31m[-] Unexpected archive content (No $ARCHIVE_DIR directory).\033[0m"
    exit 1
fi

echo -e "\033[32m[+] Moving content to installation directory...\033[0m"
[ ! -e $INSTALL_DIR ] && mkdir -p $INSTALL_DIR
[ -e $INSTALL_DIR/$ARCHIVE_DIR ] && rm -r $INSTALL_DIR/$ARCHIVE_DIR/
[ -e $JDK_DIR ] && rm $JDK_DIR
mv $ARCHIVE_DIR/ $INSTALL_DIR
ln -sf $INSTALL_DIR/$ARCHIVE_DIR/ $JDK_DIR
ln -sf $INSTALL_DIR/$ARCHIVE_DIR/ $INSTALL_DIR/default-java


echo -e "\033[32m[+] Updating alternatives...\033[0m"

gzip -9 $JDK_DIR/man/man1/*.1 >/dev/null 2>&1 &

LATEST=$((`update-alternatives --query java|grep Priority:|awk '{print $2}'|sort -n|tail -1`+1));

if [ -d "$JDK_DIR/man/man1" ];then
  for f in $JDK_DIR/man/man1/*; do
    name=`basename $f .1.gz`;
    #some files, like jvisualvm might not be links. Further assume this for corresponding man page
    if [ ! -f "/usr/bin/$name" -o -L "/usr/bin/$name" ]; then  
      if [ ! -f "$JDK_DIR/man/man1/$name.1.gz" ]; then
        name=`basename $f .1`;          #handle any legacy uncompressed pages
      fi
      update-alternatives --install /usr/bin/$name $name $JDK_DIR/bin/$name $LATEST \
      --slave /usr/share/man/man1/$name.1.gz $name.1.gz $JDK_DIR/man/man1/$name.1.gz
    fi
  done
  #File links without man pages
  [ -f $JDK_DIR/bin/java_vm ]  && update-alternatives --install /usr/bin/java_vm \
    java_vm  $JDK_DIR/jre/bin/java_vm $LATEST
  [ -f $JDK_DIR/bin/jcontrol ] && update-alternatives --install /usr/bin/jcontrol \
    jcontrol $JDK_DIR/bin/jcontrol    $LATEST
else  #no man pages available
  for f in $JDK_DIR/bin/*; do
    name=`basename $f`;
    #some files, like jvisualvm might not be links
    if [ ! -f "/usr/bin/$name" -o -L "/usr/bin/$name" ]; then
      update-alternatives --install /usr/bin/$name $name $JDK_DIR/bin/$name $LATEST
    fi
  done
fi

echo -e "\033[32m[+] Setting up Mozilla plugin...\033[0m"
#File links that apt-get misses
[ -f $JDK_DIR/bin/libnpjp2.so ] && update-alternatives --install \
  /usr/lib/mozilla/plugins/libnpjp2.so libnpjp2.so $JDK_DIR/jre/lib/i386/libnpjp2.so $LATEST

echo -e "\033[32m[+] Setting up env. variable JAVA_HOME... \033[0m"
cat > /etc/profile.d/java-home.sh << "EOF"
export JAVA_HOME="${JDK_DIR}"
export PATH="$JAVA_HOME/bin:$PATH"
EOF
sed -i -e 's,${JDK_DIR},'$JDK_DIR',g' /etc/profile.d/java-home.sh

echo -e "\033[32m[+] Checking version... \033[0m"
java -version
echo -e "\033[32m[+] Done. \033[0m"


echo -e "\033[32m[+] Downloading ElasticSearch \033[0m"
wget https://download.elasticsearch.org/elasticsearch/elasticsearch/elasticsearch-1.4.2.deb


dpkg -i elasticsearch-1.4.2.deb
update-rc.d elasticsearch defaults 95 10


echo -e "\033[32m[+] Configuration of your ElasticSearch Cluster \033[0m"
sedeasy '#cluster.name: elasticsearch' 'cluster.name: '$cluster_name'' /etc/elasticsearch/elasticsearch.yml
sedeasy '#node.name: "Franz Kafka"' 'node.name: '$node_name'' /etc/elasticsearch/elasticsearch.yml
sedeasy '#index.number_of_shards: 5' "index.number_of_shards: 1" /etc/elasticsearch/elasticsearch.yml
sedeasy '#index.number_of_replicas: 1' "index.number_of_replicas: 1" /etc/elasticsearch/elasticsearch.yml
sedeasy '#discovery.zen.ping.multicast.enabled: false' 'discovery.zen.ping.multicast.enabled: false' /etc/elasticsearch/elasticsearch.yml
sedeasy '#discovery.zen.ping.unicast.hosts: ["host1", "host2:port"]' "discovery.zen.ping.unicast.hosts: $host" /etc/elasticsearch/elasticsearch.yml

echo -e "\033[32m[+] Marvel - Turn off logging \033[0m"
echo "marvel.agent.enabled: false" >> /etc/elasticsearch/elasticsearch.yml

echo -e "\033[32m[+] Starting ElasticSearch \033[0m"
/etc/init.d/elasticsearch start > /dev/null

echo -e "\033[32m[+]  Done. \033[0m"

echo -e "\033[32m[+] Cleaning ...\033[0m"
rm jdk-8u25-linux-x64.tar.gz > /dev/null
rm elasticsearch-1.4.2.deb > /dev/null
apt-get autoclean > /dev/null

echo -e "\033[32m[+] Install all plugin of ElasticSearch \033[0m"
cd /usr/share/elasticsearch/bin
./plugin --install elasticsearch/marvel/latest > /dev/null
./plugin --install mobz/elasticsearch-head > /dev/null
./plugin --install lmenezes/elasticsearch-kopf/1.4.2 > /dev/null
./plugin --install royrusso/elasticsearch-HQ > /dev/null

echo -e "\033[32m[+] Securing your Cluster. \033[0m"

echo -e "\033[32m[+] Prohibition compile or install a paquet  for a simple user. \033[0m"
chmod o-x /usr/bin/gcc-*
chmod o-x /usr/bin/make*
chmod o-x /usr/bin/apt-get
chmod o-x /usr/bin/dpkg

echo -e "\033[32m[+] No Core Dump. \033[0m"
echo "*   hard core 0" >> /etc/security/limits.conf
echo "fs.suid_dumpable = 0" >> /etc/sysctl.conf
echo 'ulimit -S -c 0 > /dev/null 2>&1' >> /etc/profile


echo -e "\033[32m[+] Forbiden to read passwd et shadow \033[0m"
cd /etc/
chown root:root passwd shadow group gshadow
chmod 644 passwd group
chmod 400 shadow gshadow

echo -e "\033[32m[+] Enable logging of su activity . \033[0m"
sedeasy 'SYSLOG_SU_ENAB      no' 'SYSLOG_SU_ENAB      yes' /etc/login.defs
sedeasy 'SYSLOG_SG_ENAB      no' 'SYSLOG_SG_ENAB      yes' /etc/login.defs


echo -e "\033[32m[+] Backup of sshd_config \033[0m"
cp /etc/ssh/sshd_config /etc/ssh/sshd_config_backup

echo -e "\033[32m[+] Change the default SSH port\033[0m"
sedeasy '#   Port 22' '    Port $ssh_port' /etc/ssh/ssh_config

echo -e "\033[32m[+] Disable SSH login for the root user\033[0m"
sedeasy 'PermitRootLogin' 'PermitRootLogin no' /etc/ssh/ssh_config

echo -e "\033[32m[+] Update iptables \033[0m"
iptables -A INPUT  -p tcp -m tcp --dport $ssh_port -j ACCEPT

echo -e "\033[32m[+] Change configuration of Portsentry \033[0m"
sedeasy 'BLOCK_UDP="0"' 'BLOCK_UDP="1"' /etc/portsentry/portsentry.conf
sedeasy 'BLOCK_TCP="0"' 'BLOCK_TCP="1"' /etc/portsentry/portsentry.conf
sedeasy 'KILL_ROUTE="/sbin/route add -host $TARGET$ reject"' 'KILL_ROUTE="/sbin/iptables -I INPUT -s $TARGET$ -j DROP"' /etc/portsentry/portsentry.conf
sedeasy 'RESOLVE_HOST = "0"' 'RESOLVE_HOST = "1"' /etc/portsentry/portsentry.conf
sedeasy 'TCP_MODE="tcp"' 'TCP_MODE="atcp"' /etc/default/portsentry
sedeasy 'UDP_MODE="udp"' 'UDP_MODE="sudp"' /etc/default/portsentry

echo -e "\033[32m[+] Restarting portsentry \033[0m"
/etc/init.d/portsentry restart > /dev/null

echo -e "\033[32m[+] Restarting sshd \033[0m"
/etc/init.d/ssh restart

echo -e "\033[32m[+] Change configuration of Fail2Ban \033[0m"
sedeasy '/maxretry = 6' 'maxretry = 3' /etc/fail2ban/jail.conf
/etc/init.d/fail2ban restart > /dev/null