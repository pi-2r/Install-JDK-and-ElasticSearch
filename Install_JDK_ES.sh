#!/bin/bash

echo "The script installs Oracle JDK and ElasticSearch."

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root."
   exit 1
fi

echo "Debian Update"
apt-get update
apt-get dist-upgrade
echo "Downloading of JDK"
COOKIE="gpw_e24=x; oraclelicense=accept-securebackup-cookie"
wget --header="Cookie: $COOKIE" http://download.oracle.com/otn-pub/java/jdk/8u25-b17/jdk-8u25-linux-x64.tar.gz

echo "Looking for JDK archive..."
VERSION=`ls jdk-*-linux-*.tar.gz 2>/dev/null | awk -F '-' '{print $2}' | awk -F 'u' '{print $1}' | sort -n | tail -1`
UPDATE=`ls jdk-$VERSION*-linux-*.tar.gz 2>/dev/null | awk -F '-' '{print $2}' | awk -F 'u' '{print $2}' | sort -n | tail -1`
[ ! -z $UPDATE ] && UPDATE_SUFFIX="u$UPDATE"
LATEST_JDK_ARCHIVE=`ls jdk-$VERSION$UPDATE_SUFFIX-linux-*.tar.gz 2>/dev/null | sort | tail -1`
if [ -z "$LATEST_JDK_ARCHIVE" ] || [ -z "$VERSION" ]; then
    echo "Archive with JDK wasn't found. It should be in the current directory."
    exit 1
fi
echo "Found archive: $LATEST_JDK_ARCHIVE"
echo "Version: $VERSION"
[ ! -z $UPDATE ] && echo "Update: $UPDATE"

INSTALL_DIR=/usr/lib/jvm
JDK_DIR=$INSTALL_DIR/java-$VERSION-oracle

echo "Extracting archive..."
tar -xzf $LATEST_JDK_ARCHIVE
if [ $? -ne 0 ]; then
    echo "Error while extraction archive."
    exit 1
fi

ARCHIVE_DIR="jdk1.$VERSION.0"
if [ ! -z $UPDATE ]; then
  ARCHIVE_DIR=$ARCHIVE_DIR"_"`printf "%02d" $UPDATE`
fi

if [ ! -d $ARCHIVE_DIR ]; then
    echo "Unexpected archive content (No $ARCHIVE_DIR directory)."
    exit 1
fi

echo "Moving content to installation directory..."
[ ! -e $INSTALL_DIR ] && mkdir -p $INSTALL_DIR
[ -e $INSTALL_DIR/$ARCHIVE_DIR ] && rm -r $INSTALL_DIR/$ARCHIVE_DIR/
[ -e $JDK_DIR ] && rm $JDK_DIR
mv $ARCHIVE_DIR/ $INSTALL_DIR
ln -sf $INSTALL_DIR/$ARCHIVE_DIR/ $JDK_DIR
ln -sf $INSTALL_DIR/$ARCHIVE_DIR/ $INSTALL_DIR/default-java


echo "Updating alternatives..."
# The following part has been taken from script
# http://webupd8.googlecode.com/files/update-java-0.5b
# and modified to make it work without X-server.

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

echo "Setting up Mozilla plugin..."
#File links that apt-get misses
[ -f $JDK_DIR/bin/libnpjp2.so ] && update-alternatives --install \
  /usr/lib/mozilla/plugins/libnpjp2.so libnpjp2.so $JDK_DIR/jre/lib/i386/libnpjp2.so $LATEST

echo "Setting up env. variable JAVA_HOME..."
cat > /etc/profile.d/java-home.sh << "EOF"
export JAVA_HOME="${JDK_DIR}"
export PATH="$JAVA_HOME/bin:$PATH"
EOF
sed -i -e 's,${JDK_DIR},'$JDK_DIR',g' /etc/profile.d/java-home.sh

echo "Checking version..."
java -version
echo "Done."


echo "ElasticSearch"
wget https://download.elasticsearch.org/elasticsearch/elasticsearch/elasticsearch-1.4.2.deb


dpkg -i elasticsearch-1.4.2.deb
update-rc.d elasticsearch defaults 95 10
echo "Done."

echo "Cleaning ..."
rm jdk-8u25-linux-x64.tar.gz
rm elasticsearch-1.4.2.deb
apt-get autoclean