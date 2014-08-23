# RMStateStore #

----------

### 一、RM为什么要存储状态信息 ###

RM HA这项工作的目的是，当Active RM由于异常无法工作时，Standby RM能接替正在服务的Active RM，防止集群出现不可用状态。那Standby RM是如何知道正在运行的App的状态的呢？

这就需要主Active RM把App的状态保存下来，那要保存哪些状态呢？除了保存App的状态，是否还需要保存NodeManager的状态呢？

我们先从代码上来看，RM HA的org.apache.hadoop.yarn.server.resourcemanager.recovery包中，定义了一个RMStateStore接口，接口解释如下：

> Base class to implement storage of ResourceManager state. Takes care of asynchronous notifications and interfacing with YARN objects. Real store implementations need to derive from it and implement blocking store and load methods to actually store and load the state.

大致意思是，RMStateStore是存储ResourceManager状态的基础接口（抽象类），真实的存储器需要实现存储和加载方法。

----------

### 二、RM类元素和存储的状态 ###

组成元素：

![](https://github.com/loull521/hadoop-yarn-src-read/raw/master/raw/pictures/RMStateStore/RMStateStore.png)

可以看到有四个内部类，分别是：

- RMState
- ApplicationState
- ApplicationAttemptState
- RMDTSecretManagerState

下面是保存、更新、删除状态：

![](https://github.com/loull521/hadoop-yarn-src-read/raw/master/raw/pictures/RMStateStore/RMStateStore_crud.png)

----------

### 三、什么时候存储状态 ###

总结一句：在应该保持的时候保持，状态改变很大的时候更新。

#### 1、storeNewApplication ####

RMAppEvent的START事件

#### 2、updateApplicationState ####

RMAppState.NEW_SAVING状态，遇到RMAppEventType.KILL事件，

RMAppState.ACCEPTED和RMAppState.RUNNING状态，遇到RMAppEventType.ATTEMPT_FAILED。

RM通过AttemptFailedTransition和FinalSavingTransition方法调用了更新。

#### 3、storeNewApplicationAttempt ####

RMAppAttemptState.SCHEDULED状态遇到RMAppAttemptEventType.CONTAINER_ALLOCATED事件时调用AMContainerAllocatedTransition。

#### 4、updateApplicationAttemptState ####

调用AMUnregisteredTransition，ContainerFinishedTransition，FinalSavingTransition这三个方法都会发生状态更新。

出触发调用这三个方法的情况：

RMAppAttemptState.RUNNING遇到RMAppAttemptState.FINISHED事件时调用AMUnregisteredTransition，遇到RMAppAttemptEventType.CONTAINER_FINISHED时调用ContainerFinishedTransition。

调用FinalSavingTransition的地方比较多，如下所示，总结起来就是Attempt遇到非正常状态下的状态转换关系。

----------

### 四、如何存储状态信息 ###

RMStateStore只实现了存储状态的接口，具体的存储方法由实现类完成：

![](https://github.com/loull521/hadoop-yarn-src-read/raw/master/raw/pictures/RMStateStore/RMStateStore_inherit.jpg)

`NullRMStateStore`的实现都为空方法。

`MemoryRMStateStore` 使用RMStats对象存储所有RM的状态，并在内存中维护。

`FileSystemRMStateStore` 中，由配置`yarn.resourcemanager.fs.state-store.uri`决定存储的位置，由代码：

	fs = fsWorkingPath.getFileSystem(conf)
可以是本地文件，也可以是HDFS。

`ZKRMStateStore` 把RM状态存储到ZK上，目录结构如下所示：

	   ROOT_DIR_PATH
	   |--- VERSION_INFO
	   |--- RM_ZK_FENCING_LOCK
	   |--- RM_APP_ROOT
	   |     |----- (#ApplicationId1)
	   |     |        |----- (#ApplicationAttemptIds)
	   |     |
	   |     |----- (#ApplicationId2)
	   |     |       |----- (#ApplicationAttemptIds)
	   |     ....
	   |
	   |--- RM_DT_SECRET_MANAGER_ROOT
	          |----- RM_DT_SEQUENTIAL_NUMBER_ZNODE_NAME
	          |----- RM_DELEGATION_TOKENS_ROOT_ZNODE_NAME
	          |       |----- Token_1
	          |       |----- Token_2
	          |       ....
	          |
	          |----- RM_DT_MASTER_KEYS_ROOT_ZNODE_NAME
	          |      |----- Key_1
	          |      |----- Key_2
                  ....

在ZKRMStateStore中，所有对ZK的操作都加上了隔离机制，防止多个client对ZK同一目录的操作。

----------

### 五、RM什么时候还原状态和怎么还原状态 ###

只有在RMActiveService启动的时候才会调用loadState方法，加载已经存储的RM的状态。需要指出的是，RM支持HA后，RM中的服务已经分为Always on和Active两部分，Always on的服务会在Active和Standby RM上启动，而Active服务只会在Active RM上启动，而RM启动后默认进入Standby，当前只能手动出发RM转换为Active，这时候RM就会加载已经存储的状态并还原了。

