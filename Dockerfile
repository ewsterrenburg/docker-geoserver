#--------- Generic stuff all our Dockerfiles should start with so we get caching ------------
FROM tomcat:8.0-jre8
MAINTAINER Tim Sutton<tim@linfiniti.com>

RUN  export DEBIAN_FRONTEND=noninteractive
ENV  DEBIAN_FRONTEND noninteractive
RUN  dpkg-divert --local --rename --add /sbin/initctl
#RUN  ln -s /bin/true /sbin/initctl

RUN apt-get -y update

#Install extra fonts to use with sld font markers
RUN apt-get install -y  fonts-cantarell lmodern ttf-aenigma ttf-georgewilliams ttf-bitstream-vera ttf-sjfonts tv-fonts \
    build-essential libapr1-dev libssl-dev default-jdk
#-------------Application Specific Stuff ----------------------------------------------------

ENV GS_VERSION 2.12.2
ENV GEOSERVER_DATA_DIR /opt/geoserver/data_dir
ENV ENABLE_JSONP false
ENV MAX_FILTER_RULES 20
ENV OPTIMIZE_LINE_WIDTH false
ENV GEOWEBCACHE_CACHE_DIR /opt/geoserver/data_dir/gwc


ENV GEOSERVER_OPTS "-Djava.awt.headless=true -server -Xms2G -Xmx4G -Xrs -XX:PerfDataSamplingInterval=500 \
 -Dorg.geotools.referencing.forceXY=true -XX:SoftRefLRUPolicyMSPerMB=36000 -XX:+UseParallelGC -XX:NewRatio=2 \
 -XX:+CMSClassUnloadingEnabled"
#-XX:+UseConcMarkSweepGC use this rather than parallel GC?  
ENV JAVA_OPTS "$JAVA_OPTS $GEOSERVER_OPTS"
ENV GDAL_DATA /usr/local/gdal_data
ENV LD_LIBRARY_PATH /usr/local/gdal_native_libs:/usr/local/apr/lib:/opt/libjpeg-turbo/lib64
ENV GEOSERVER_LOG_LOCATION /opt/geoserver/data_dir/logs/geoserver.log

RUN mkdir -p $GEOSERVER_DATA_DIR

# Unset Java related ENVs since they may change with Oracle JDK
ENV JAVA_VERSION=
ENV JAVA_DEBIAN_VERSION=

# Set JAVA_HOME to /usr/lib/jvm/default-java and link it to OpenJDK installation
RUN ln -s /usr/lib/jvm/java-8-openjdk-amd64 /usr/lib/jvm/default-java
ENV JAVA_HOME /usr/lib/jvm/default-java

ADD resources /tmp/resources

# Install libjpeg-turbo for that specific geoserver version
RUN if [ ! -f /tmp/resources/libjpeg-turbo-official_1.5.3_amd64.deb ]; then \
    wget https://tenet.dl.sourceforge.net/project/libjpeg-turbo/1.5.3/libjpeg-turbo-official_1.5.3_amd64.deb -P ./resources;\
    fi; \
    cd /tmp/resources/ && \
    dpkg -i libjpeg-turbo-official_1.5.3_amd64.deb


# Install tomcat APR
RUN if [ ! -f /tmp/resources/apr-1.6.3.tar.gz ]; then \
    wget -c wget  http://mirror.za.web4africa.net/apache//apr/apr-1.6.3.tar.gz \
      -P ./resources; \
    fi; \
    tar -xzf /tmp/resources/apr-1.6.3.tar.gz -C /tmp/resources/ && \
    cd /tmp/resources/apr-1.6.3 && \
    touch libtoolT && ./configure && make -j 4 && make install

# Install tomcat native
RUN if [ ! -f /tmp/resources/tomcat-native-1.2.16-src.tar.gz ]; then \
    wget -c http://mirror.za.web4africa.net/apache/tomcat/tomcat-connectors/native/1.2.16/source/tomcat-native-1.2.16-src.tar.gz \
      -P ./resources; \
    fi; \
    tar -xzf /tmp/resources/tomcat-native-1.2.16-src.tar.gz -C /tmp/resources/ && \
    cd /tmp/resources/tomcat-native-1.2.16-src/native && \
    ./configure --with-java-home=${JAVA_HOME} --with-apr=/usr/local/apr && make -j 4 && make install


# If a matching Oracle JDK tar.gz exists in /tmp/resources, move it to /var/cache/oracle-jdk8-installer
# where oracle-java8-installer will detect it
RUN if ls /tmp/resources/*jdk-*-linux-x64.tar.gz > /dev/null 2>&1; then \
      mkdir /var/cache/oracle-jdk8-installer && \
      mv /tmp/resources/*jdk-*-linux-x64.tar.gz /var/cache/oracle-jdk8-installer/; \
    fi;

# Install Oracle JDK (and uninstall OpenJDK JRE) if the build-arg ORACLE_JDK = true or an Oracle tar.gz
# was found in /tmp/resources
ARG ORACLE_JDK=false
RUN if ls /var/cache/oracle-jdk8-installer/*jdk-*-linux-x64.tar.gz > /dev/null 2>&1 || [ "$ORACLE_JDK" = true ]; then \
       apt-get autoremove --purge -y openjdk-8-jre-headless && \
       echo oracle-java8-installer shared/accepted-oracle-license-v1-1 select true \
         | debconf-set-selections && \
       echo "deb http://ppa.launchpad.net/webupd8team/java/ubuntu xenial main" \
         > /etc/apt/sources.list.d/webupd8team-java.list && \
       apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys EEA14886 && \
       rm -rf /var/lib/apt/lists/* && \
       apt-get update && \
       apt-get install -y oracle-java8-installer oracle-java8-set-default && \
       ln -s --force /usr/lib/jvm/java-8-oracle /usr/lib/jvm/default-java && \
       rm -rf /var/lib/apt/lists/* && \
       rm -rf /var/cache/oracle-jdk8-installer; \
       if [ -f /tmp/resources/jce_policy.zip ]; then \
         unzip -j /tmp/resources/jce_policy.zip -d /tmp/jce_policy && \
         mv /tmp/jce_policy/*.jar $JAVA_HOME/jre/lib/security/; \
       fi; \
    fi;

#Add JAI and ImageIO for great speedy speed.
WORKDIR /tmp
# A little logic that will fetch the JAI and JAI ImageIO tar file if it
# is not available locally in the resources dir
RUN if [ ! -f /tmp/resources/jai-1_1_3-lib-linux-amd64.tar.gz ]; then \
    wget http://download.java.net/media/jai/builds/release/1_1_3/jai-1_1_3-lib-linux-amd64.tar.gz -P ./resources;\
    fi; \
    if [ ! -f /tmp/resources/jai_imageio-1_1-lib-linux-amd64.tar.gz ]; then \
    wget http://download.java.net/media/jai-imageio/builds/release/1.1/jai_imageio-1_1-lib-linux-amd64.tar.gz -P ./resources;\
    fi; \
    mv resources/jai-1_1_3-lib-linux-amd64.tar.gz ./ && \
    mv resources/jai_imageio-1_1-lib-linux-amd64.tar.gz ./ && \
    gunzip -c jai-1_1_3-lib-linux-amd64.tar.gz | tar xf - && \
    gunzip -c jai_imageio-1_1-lib-linux-amd64.tar.gz | tar xf - && \
    mv /tmp/jai-1_1_3/lib/*.jar $JAVA_HOME/jre/lib/ext/ && \
    mv /tmp/jai-1_1_3/lib/*.so $JAVA_HOME/jre/lib/amd64/ && \
    mv /tmp/jai_imageio-1_1/lib/*.jar $JAVA_HOME/jre/lib/ext/ && \
    mv /tmp/jai_imageio-1_1/lib/*.so $JAVA_HOME/jre/lib/amd64/ && \
    rm /tmp/jai-1_1_3-lib-linux-amd64.tar.gz && \
    rm -r /tmp/jai-1_1_3 && \
    rm /tmp/jai_imageio-1_1-lib-linux-amd64.tar.gz && \
    rm -r /tmp/jai_imageio-1_1
WORKDIR $CATALINA_HOME

# A little logic that will fetch the geoserver war zip file if it
# is not available locally in the resources dir
RUN if [ ! -f /tmp/resources/geoserver-${GS_VERSION}.zip ]; then \
    wget -c http://downloads.sourceforge.net/project/geoserver/GeoServer/${GS_VERSION}/geoserver-${GS_VERSION}-war.zip \
      -O /tmp/resources/geoserver-${GS_VERSION}.zip; \
    fi; \
    unzip /tmp/resources/geoserver-${GS_VERSION}.zip -d /tmp/geoserver \
    && unzip /tmp/geoserver/geoserver.war -d $CATALINA_HOME/webapps/geoserver \
    && rm -rf $CATALINA_HOME/webapps/geoserver/data \
    && rm -rf /tmp/geoserver

# Install any plugin zip files in resources/plugins
RUN if ls /tmp/resources/plugins/*.zip > /dev/null 2>&1; then \
      for p in /tmp/resources/plugins/*.zip; do \
        unzip $p -d /tmp/gs_plugin \
        && mv /tmp/gs_plugin/*.jar $CATALINA_HOME/webapps/geoserver/WEB-INF/lib/ \
        && rm -rf /tmp/gs_plugin; \
      done; \
    fi; \
    if ls /tmp/resources/plugins/*gdal*.tar.gz > /dev/null 2>&1; then \
    mkdir /usr/local/gdal_data && mkdir /usr/local/gdal_native_libs; \
    unzip /tmp/resources/plugins/gdal/gdal-data.zip -d /usr/local/gdal_data && \
    tar xzf /tmp/resources/plugins/gdal192-Ubuntu12-gcc4.6.3-x86_64.tar.gz -C /usr/local/gdal_native_libs; \
    fi;

# Overlay files and directories in resources/overlays if they exist
RUN rm -f /tmp/resources/overlays/README.txt && \
    if ls /tmp/resources/overlays/* > /dev/null 2>&1; then \
      cp -rf /tmp/resources/overlays/* /; \
    fi;

# Optionally remove Tomcat manager, docs, and examples
ARG TOMCAT_EXTRAS=true
RUN if [ "$TOMCAT_EXTRAS" = false ]; then \
    rm -rf $CATALINA_HOME/webapps/ROOT && \
    rm -rf $CATALINA_HOME/webapps/docs && \
    rm -rf $CATALINA_HOME/webapps/examples && \
    rm -rf $CATALINA_HOME/webapps/host-manager && \
    rm -rf $CATALINA_HOME/webapps/manager; \
  fi;

# Delete resources after installation
RUN rm -rf /tmp/resources
