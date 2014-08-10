# YARN 框架介绍 #

## 一、yarn资源调度 ##

yarn架构图：

![](https://github.com/loull521/hadoop-yarn-src-read/raw/master/raw/pictures/yarn/yarn_architecture.gif)

## 二、yarn通信协议简介 ##

![](https://github.com/loull521/hadoop-yarn-src-read/raw/master/raw/pictures/yarn/protocol.png)

#### ApplicationClientProtocol： ####

APP客户端向提交、查询、控制app

#### ApplicationMasterProtocol： ####

AM向注册、申请和释放资源

#### ContainerManagementProtocol ####

AM向NM发起针对Container的相关操

### ResourceTracker ###

NM 向RM注册，汇报Container状态并领取命令


## 三、yarn HA 高可用 ##

![](https://github.com/loull521/hadoop-yarn-src-read/raw/master/raw/pictures/yarn/rm-ha-overview.png)