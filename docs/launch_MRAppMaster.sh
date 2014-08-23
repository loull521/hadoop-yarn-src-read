#!/bin/bash

export YARN_LOCAL_DIRS="/tmp/nm-local-dir/usercache/yarn/appcache/application_1350707900707_0003"
export NM_HTTP_PORT="8042"
export JAVA_HOME="/usr/lib/jvm/java-1.6.0-openjdk-1.6.0.0.x86_64/jre"
export NM_HOST="hd19-vm4.yunti.yh.aliyun.com"
export CLASSPATH="$PWD:$HADOOP_CONF_DIR:$HADOOP_COMMON_HOME/share/hadoop/common/*:$HADOOP_COMMON_HOME/share/hadoop/common/lib/*:$HADOOP_HDFS_HOME/share/hadoop/hdfs/*:$HADOOP_HDFS_HOME/share/hadoop/hdfs/lib/*:$YARN_HOME/share/hadoop/mapreduce/*:$YARN_HOME/share/hadoop/mapreduce/lib/*:job.jar:$PWD/*"
export HADOOP_TOKEN_FILE_LOCATION="/tmp/nm-local-dir/usercache/yarn/appcache/application_1350707900707_0003/container_1350707900707_0003_01_000001/container_tokens"
export APPLICATION_WEB_PROXY_BASE="/proxy/application_1350707900707_0003"
export JVM_PID="$$"
export USER="yarn"
export PWD="/tmp/nm-local-dir/usercache/yarn/appcache/application_1350707900707_0003/container_1350707900707_0003_01_000001"
export NM_PORT="49111"
export HOME="/home/"
export LOGNAME="yarn"
export APP_SUBMIT_TIME_ENV="1350788662618"
export HADOOP_CONF_DIR="/home/yarn/hadoop-2.0.0-alpha/conf"
export MALLOC_ARENA_MAX="4"
export AM_CONTAINER_ID="container_1350707900707_0003_01_000001"
ln -sf "/tmp/nm-local-dir/usercache/yarn/appcache/application_1350707900707_0003/filecache/-5059634618081520617/job.jar" "job.jar"
mkdir -p jobSubmitDir
ln -sf "/tmp/nm-local-dir/usercache/yarn/appcache/application_1350707900707_0003/filecache/8471400424465082106/appTokens" "jobSubmitDir/appTokens"
ln -sf "/tmp/nm-local-dir/usercache/yarn/appcache/application_1350707900707_0003/filecache/-511993817008097803/job.xml" "job.xml"
mkdir -p jobSubmitDir
ln -sf "/tmp/nm-local-dir/usercache/yarn/appcache/application_1350707900707_0003/filecache/5917092335430839370/job.split" "jobSubmitDir/job.split"
mkdir -p jobSubmitDir
ln -sf "/tmp/nm-local-dir/usercache/yarn/appcache/application_1350707900707_0003/filecache/5764499011863329844/job.splitmetainfo" "jobSubmitDir/job.splitmetainfo"
exec /bin/bash -c "$JAVA_HOME/bin/java -Dlog4j.configuration=container-log4j.properties -Dyarn.app.mapreduce.container.log.dir=/tmp/logs/application_1350707900707_0003/container_1350707900707_0003_01_000001 -Dyarn.app.mapreduce.container.log.filesize=0 -Dhadoop.root.logger=INFO,CLA -Xmx1024m org.apache.hadoop.mapreduce.v2.app.MRAppMaster 1>/tmp/logs/application_1350707900707_0003/container_1350707900707_0003_01_000001/stdout 2>/tmp/logs/application_1350707900707_0003/container_1350707900707_0003_01_000001/stderr  "