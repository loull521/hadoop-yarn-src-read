# NodeManager （一） #

## 一、NM各个组件 ##

![](https://github.com/loull521/hadoop-yarn-src-read/raw/master/raw/pictures/nm/Node-Manager-Diagram.png)

#### 1、NodeStatusUpdate ####

> NM与RM通信的**唯一**通道

- 注册
- 心跳：汇报container信息，收到RM的response，清理container等操作。

#### 2、ContainerManager ####

- `RPC server`
- `ResourceLocalizationService`：负责container所需资源的本地化，比如从hdfs下载资源。
- `ContainerLauncher`：维护了一个线程池完成Container相关操作。比如启动或杀死container。**启动**是有`ApplicationMaster`发起的，**杀死**container请求可能来自`ApplicationMaster`或者`ResourceManager`。
- `AuxManager`
- `ContainerMonitor`
- `LogHandler`
- `ContainerEventHandler`

#### 3、ContainerExecutor ####

可与底层操作系统交互，安全存放container需要的文件和目录。

#### 4、NodeHealthCheckService ####

#### 5、DeletionService ####

提供异步删除失效文件服务

#### 6、Security ####

#### 7、WebServer ####

## 二、NM内部状态机组件 ##

### 1、Application状态机 ###

![](https://github.com/loull521/hadoop-yarn-src-read/raw/master/raw/pictures/nm/nm_application.png)

----------

### 2、Container状态机 ###

![](https://github.com/loull521/hadoop-yarn-src-read/raw/master/raw/pictures/nm/nm_container.png)

----------

### 3、LocalizationResource状态机 ###

![](https://github.com/loull521/hadoop-yarn-src-read/raw/master/raw/pictures/nm/nn_LocalizedResource.png)

## 三、container启动流程 ##



1. `ContainerManagerImpl`收到`startContainers`RPC请求。更新NMToken。创建`ContainerImpl`状态机，发送`ApplicationEventType.INIT_APPLICATION`(如果这个NM上还没有applicationImpl状态机)和`ApplicationEventType.INIT_CONTAINER`事件。
2. `ApplicationImpl`处理这两个事件。(1)发送一个记录日志的事件。(2)找出`ApplicationEventType.INIT_CONTAINER`事件对应的container，添加到app持有的containers集合。