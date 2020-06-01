#--------- Generic stuff all our Dockerfiles should start with so we get caching ------------
FROM tomcat:9.0-jre11-slim
LABEL maintainer="Borhaneddine GUEMIDI <guemidiborhane@aina.dz>"

#Credit: thinkWhere<info@thinkwhere.com>
# thinkWhere/GeoServer-Docker

RUN  export DEBIAN_FRONTEND=noninteractive
ENV  DEBIAN_FRONTEND noninteractive
RUN  dpkg-divert --local --rename --add /sbin/initctl
#RUN  ln -s /bin/true /sbin/initctl

# Use local cached debs from host (saves your bandwidth!)
# Change ip below to that of your apt-cacher-ng host
# Or comment this line out if you do not with to use caching
# ADD 71-apt-cacher-ng /etc/apt/apt.conf.d/71-apt-cacher-ng

RUN apt-get -y update && apt-get -y install wget

#-------------Application Specific Stuff ----------------------------------------------------

ARG GS_VERSION=2.16.3
ARG GS_DATA_DIR=/opt/geoserver/data_dir
ENV GEOSERVER_DATA_DIR=$GS_DATA_DIR

RUN mkdir -p $GS_DATA_DIR

# Unset Java related ENVs since they may change with Oracle JDK
ENV JAVA_VERSION=
ENV JAVA_DEBIAN_VERSION=

# Set JAVA_HOME to /usr/lib/jvm/default-java and link it to OpenJDK installation
RUN ln -s /usr/lib/jvm/java-11-openjdk-amd64 /usr/lib/jvm/default-java
ENV JAVA_HOME /usr/lib/jvm/default-java

ADD resources /tmp/resources

# Optionally add JAI and ImageIO for improved performance. # not supported by jre11
WORKDIR /tmp
#ARG JAI_IMAGEIO=true
#RUN if [ "$JAI_IMAGEIO" = true ]; then \
#    wget http://download.java.net/media/jai/builds/release/1_1_3/jai-1_1_3-lib-linux-amd64.tar.gz && \
#    wget http://download.java.net/media/jai-imageio/builds/release/1.1/jai_imageio-1_1-lib-linux-amd64.tar.gz && \
#    gunzip -c jai-1_1_3-lib-linux-amd64.tar.gz | tar xf - && \
#    gunzip -c jai_imageio-1_1-lib-linux-amd64.tar.gz | tar xf - && \
#    mv /tmp/jai-1_1_3/lib/*.jar $JAVA_HOME/jre/lib/ext/ && \
#    mv /tmp/jai-1_1_3/lib/*.so $JAVA_HOME/jre/lib/amd64/ && \
#    mv /tmp/jai_imageio-1_1/lib/*.jar $JAVA_HOME/jre/lib/ext/ && \
#    mv /tmp/jai_imageio-1_1/lib/*.so $JAVA_HOME/jre/lib/amd64/ && \
#    rm /tmp/jai-1_1_3-lib-linux-amd64.tar.gz && \
#    rm -r /tmp/jai-1_1_3 && \
#    rm /tmp/jai_imageio-1_1-lib-linux-amd64.tar.gz && \
#    rm -r /tmp/jai_imageio-1_1; \
#    fi

# Add GDAL native libraries if the build-arg GDAL_NATIVE = true
ARG GDAL_NATIVE=false
# EWC and JP2ECW are subjected to licence restrictions
ENV GDAL_SKIP "ECW JP2ECW"
ENV GDAL_DATA $CATALINA_HOME/gdal-data
ENV LD_LIBRARY_PATH $JAVA_HOME/jre/lib/amd64/gdal
RUN if [ "$GDAL_NATIVE" = true ]; then \
    wget http://demo.geo-solutions.it/share/github/imageio-ext/releases/1.1.X/1.1.16/native/gdal/gdal-data.zip && \
    wget http://demo.geo-solutions.it/share/github/imageio-ext/releases/1.1.X/1.1.16/native/gdal/linux/gdal192-Ubuntu12-gcc4.6.3-x86_64.tar.gz && \
    unzip gdal-data.zip -d $CATALINA_HOME && \
    mkdir $JAVA_HOME/jre/lib/amd64/gdal && \
    tar -xvf gdal192-Ubuntu12-gcc4.6.3-x86_64.tar.gz -C $LD_LIBRARY_PATH; \
    fi

# If using GDAL make sure extension is downloaded
RUN if [ "$GDAL_NATIVE" = true ] && [ ! -f /tmp/resources/plugins/geoserver-gdal-plugin.zip ]; then \
    wget -c http://downloads.sourceforge.net/project/geoserver/GeoServer/${GS_VERSION}/extensions/geoserver-${GS_VERSION}-gdal-plugin.zip \
    -O /tmp/resources/plugins/geoserver-gdal-plugin.zip; \
    fi;

WORKDIR $CATALINA_HOME

# Fetch the geoserver war file if it
# is not available locally in the resources dir and
RUN if [ ! -f /tmp/resources/geoserver.zip ]; then \
    wget -c http://downloads.sourceforge.net/project/geoserver/GeoServer/${GS_VERSION}/geoserver-${GS_VERSION}-war.zip \
    -O /tmp/resources/geoserver.zip; \
    fi; \
    unzip /tmp/resources/geoserver.zip -d /tmp/geoserver \
    && mv /tmp/geoserver/geoserver.war /tmp/geoserver/ROOT.war \
    && rm -rf $CATALINA_HOME/webapps/ROOT \
    && unzip /tmp/geoserver/ROOT.war -d $CATALINA_HOME/webapps/ROOT \
    && rm -rf $CATALINA_HOME/ROOT/geoserver/data \
    && rm -rf /tmp/geoserver

# Install any plugin zip files in resources/plugins
RUN if ls /tmp/resources/plugins/*.zip > /dev/null 2>&1; then \
    for p in /tmp/resources/plugins/*.zip; do \
    unzip $p -d /tmp/gs_plugin \
    && mv /tmp/gs_plugin/*.jar $CATALINA_HOME/webapps/ROOT/WEB-INF/lib/ \
    && rm -rf /tmp/gs_plugin; \
    done; \
    fi;

# Overlay files and directories in resources/overlays if they exist
RUN if ls /tmp/resources/overlays/* > /dev/null 2>&1; then \
    cp -rf /tmp/resources/overlays/* /; \
    fi;

# install Font files in resources/fonts if they exist
RUN if ls /tmp/resources/fonts/*.ttf > /dev/null 2>&1; then \
    cp -rf /tmp/resources/fonts/*.ttf /usr/share/fonts/truetype/; \
    fi;

# Optionally disable GeoWebCache
# (Note that this forcibly removes all gwc files. This may cause errors with extensions that depend on gwc files
#   including:  Inspire; Control-Flow; )
ARG DISABLE_GWC=false
RUN if [ "$DISABLE_GWC" = true ]; then \
    rm $CATALINA_HOME/webapps/geoserver/WEB-INF/lib/*gwc*; \
    fi;

# Optionally remove Tomcat manager, docs, and examples
ARG TOMCAT_EXTRAS=false
RUN if [ "$TOMCAT_EXTRAS" = false ]; then \
    rm -rf $CATALINA_HOME/webapps/docs && \
    rm -rf $CATALINA_HOME/webapps/examples && \
    rm -rf $CATALINA_HOME/webapps/host-manager && \
    rm -rf $CATALINA_HOME/webapps/manager; \
    fi;

# Delete resources after installation
RUN rm -rf /tmp/resources

ARG GROUP_ID
ARG USER_ID

RUN groupadd -f --gid $GROUP_ID user
RUN adduser --disabled-password --gecos '' --uid $USER_ID --gid $GROUP_ID user
RUN mkdir -p $GS_DATA_DIR && chown user:user $GS_DATA_DIR
RUN chown -R user:user $CATALINA_HOME
USER user


#ENV GEOSERVER_HOME /opt/geoserver

#ENTRYPOINT "/opt/geoserver/bin/startup.sh"
#CMD "/opt/geoserver/bin/startup.sh"
EXPOSE 8080
