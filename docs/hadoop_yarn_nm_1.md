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

Container启动过程主要经历三个阶段：

- 资源本地化
- 启动并运行Container
- 资源清理

![](https://github.com/loull521/hadoop-yarn-src-read/raw/master/raw/pictures/nm/nm_start_container_2.png)

> 注意:
> 某个AM第一次在这个NM节点要求启动container，启动这第一个container时，要创建一个applicationImpl状态机。对应图中的`(2.2, 2.5, 2.6)`操作。

----------

#### 大致过程 ####

1. RM或者appMaster通过协议发送`startContainers` RPC请求后，`ContainerManagerImpl`处理这次调用，开始初始化`applicationImpl`、`containerImpl`，注册`AuxServices`。对应图中`1~4`。
2. 资源下载：5
	1. 启动一个进程`containerLocalier`专门负责下载。
	2. `containerLocalier`通过心跳报告进度。
	3. 下载完成后触发事件给`containerImpl`。
3. `containerImpl`通过`containersLauncher`启动`container`。
4. 当`container`退出时，containersLauncher会发送事件给`containerImpl`，再完成一些资源的释放。

----------

#### 详细过程 ####

1. `ContainerManagerImpl`收到`startContainers`RPC请求。更新NMToken。创建`ContainerImpl`状态机，发送`ApplicationEventType.INIT_APPLICATION`(如果这个NM上还没有`applicationImpl`状态机，先创建`applicationImpl`状态机)和`ApplicationEventType.INIT_CONTAINER`事件。
2. `ApplicationImpl`处理这两个事件。
	1. 发送一个记录日志的事件。然后发送一个`ApplicationEventType.APPLICATION_LOG_HANDLING_INITED`事件。`ApplicationImpl`处理这个事件状态不变，还是`INITING`，然后发送一个`LocalizationEventType.INIT_APPLICATION_RESOURCES`事件。
		1. `ResourceLocalizationService`处理这个事件。先创建一个application tracker structs应用跟踪数据结构。然后发送`ApplicationEventType.APPLICATION_INITED`事件。
		2. `ApplicationImpl`处理这个事件，状态从`INITING`变为`RUNNING`。然后再发送`ContainerEventType.INIT_CONTAINER`事件。到这里，对于是否是第一次在这个NM上启动没有关系了，已经一致了。
	2. 找出`ApplicationEventType.INIT_CONTAINER`事件对应的container，添加到app持有的containers集合。如果这时候`ApplicationImpl`的状态是`INITING`，什么都不做了，知道状态变为`RUNNING`。然后发送一个`ContainerEventType.INIT_CONTAINER`事件。
3. `ContainerImpl`处理`ContainerEventType.INIT_CONTAINER`事件。先查看需要的资源，把 PUBLIC,PRIVATE,APPLICATION 级别的资源请求放到Container的不同列表里面，然后把这些请求放到map里面，再封装到事件中，发出`LocalizationEventType.INIT_CONTAINER_RESOURCES`资源请求事件。如果有需要请求下载的资源，返回`ContainerState.LOCALIZING`状态；否则，发送`ContainersLauncherEventType.LAUNCH_CONTAINER`启动container事件，返回`ContainerState.LOCALIZED`状态。
4. 不解释
5. `ResourceLocalizationService`处理`INIT_CONTAINER_RESOURCES`事件。对于每一类资源请求，创建一个`LocalResourcesTrackerImpl`进行跟踪，然后调用`tracker#handle(ResourceEventType.REQUEST)`,这里表示不用中央异步处理器出处理这个事件，而是同步调用，在这个handle方法里面，会先创建一个`LocalizedResource`状态机。然后交个这个状态机去处理`ResourceEventType.REQUEST`事件。
	1. （5.2）`LocalizdResource`处理`ResourceEventType.REQUEST`事件，状态从`INIT`变为`DOWNLOADING`。发送`LocalizerEventType.REQUEST_RESOURCE_LOCALIZATION`事件。
	2. （5.3）`LocalizerTracker`处理这个事件，如果要请求的资源类型是`APPLICATION`，会创建一个`LocalizerRunner`去异步处理资源请求。
	3. （5.4）调用`ContainerExecutor#startLocalizer`去本地化资源。`ContainerExecutor`是抽象类，这里用它的子类`LinuxContainerExecutor`为例。这里是为了启动`ContainerLocalizer`类。先创建执行命令集合command，设置好command之后，用shell的实例去执行command，这个过程实际上运行的是`ContainerLocalizer`的 main 方法，main方法里面调用 `runLocalization`方法，先获取一个 `LocalizationProtocol`协议代理，通过发心跳的方式跟`ResourceLocalizationService`通信。`ResourceLocalizationService`实现了`LocalizationProtocol`协议，维护了各种待下载资源列表。ContainerLocalizer 通过心跳不同获取要下载的资源信息，然后下载资源到特定目录里面。具体的下载过程在`FSDownload#call()`里面，
	4. （5.5）`ResourceLocalizationService`处理heartbeat，经过处理，发送`ResourceEventType.LOCALIZED`事件。
	5. （5.6）`LocalizedResource`状态机处理`ResourceEventType.LOCALIZED`事件，状态从`DOWNLOADING`变为`LOCALIZED`。然后发送`ContainerEventType.RESOURCE_LOCALIZED`事件。


待续。。。

Point：

- 资源本地化
- 过程中有一些记录history到文件系统的事件，这部分省略
- 还有一些组册到推测监听器的事件，也省略


问题：

- LocalizationProtocol协议的heartbeat请求的参数和返回数据。
- `FSDownload#call()`下载文件代码没太明白

