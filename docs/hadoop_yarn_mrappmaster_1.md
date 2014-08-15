# MRAppMaster(一) #

## MRAppMaster 各个组件 ##

![](https://github.com/loull521/hadoop-yarn-src-read/raw/master/raw/pictures/am/MRAppMaster.png)

- `ContainerAllocate`心跳，周期性与RM通信，为MR作业申请资源。
- `MRClientService`实现了`MRClientProtocol`协议，客户端通过这个协议获取作业的执行状态，和作业控制。不必通过RM了。
- `TaskCleaner`维护一个线程池和共享队列，异步垃圾数据。
- `Speculator`完成推测执行功能。当同一个作业的某个任务运行速度明显慢于其他任务，它会为该任务启动一个备用任务。**在同一个NM节点上启动备用任务吗？**
- `ContainerLauncher`与NM通信，启动Container(MRYarnChild)。当RM为作业分配资源后，ContainerLauncher会填充相关信息到Container中，包括任务运行所需资源、任务运行命令、任务运行环境、任务依赖的外部文件，然后与对应的NM通信，要求它启动container。
- `TaskAttemptListener`负责管理各个任务的心跳信息，实现了TaskUmbilicalProtocol协议。
- `JobHistoryEventHandler`

----------

- `Job`维护一个状态机JobImpl。
- `Task`维护一个任务状态机TaskImpl。
- `TaskAttemp`与MRv1的MapTask和ReduceTask运行实例完全一致。

## 二、状态机 ##

### 1、JobImpl状态机 ###

![](https://github.com/loull521/hadoop-yarn-src-read/raw/master/raw/pictures/am/JobImpl.png)

----------

### 2、TaskImpl状态机 ###

![](https://github.com/loull521/hadoop-yarn-src-read/raw/master/raw/pictures/am/TaskImpl.png)

----------

### 3、TaskAttemptImpl状态机 ###

![](https://github.com/loull521/hadoop-yarn-src-read/raw/master/raw/pictures/am/TaskAttemptImpl.png)

----------

### 4、MRAppMaster内部事件交互 ###

![](https://github.com/loull521/hadoop-yarn-src-read/raw/master/raw/pictures/am/MRInter.png)

## 三、MRAppMaster启动流程 ##

![](https://github.com/loull521/hadoop-yarn-src-read/raw/master/raw/pictures/am/MRApp_start.png)

#### 大致过程 ####

1. `MRAppMaster` 启动最后一步会发送启动 JobImpl 的事件，后初始化 TaskImpl 及 TaskAttemptImpl。1、2、3、4、5
2. `ContainerAllocator` 自身有一个线程固定周期循环获取资源，当获取后再发事件给 TaskAttemptImpl。5.2、6
3. `TaskAttemptImpl` 发送事件给 ContainerLauncher。7
4. `ContainerLauncher` 通过 NM 启动 MRYarnChild，再发送消息给 TaskAttemptImpl。8、9、10
5. `MRYarnChild` 调用接口 done()，后资源清理，后一个 task 就完成了。n1、n2
6. `TaskAttemptImpl` 会清理 container 资源(基本是 kill)，再发送完成消息给 TaskImpl。n3、n4、n5
7. 每次一个 task 完成，都会通知 JobImpl，会判断是否所有的 task 完成，如果完成则发送作业完成的消息给 MRAppMaster,
MRAppMaster 则会启动 stop()流程，依次释放资源，清理资源等。n6、n7

#### 详细过程 ####

1. `MRAppMaster`启动的最后发出 `JobEventType.JOB_INIT` 事件，然后直接同步调用处理器去处理这个事件(非异步)。初始化 job 信息，并且创建 `mapTask` 和 `reduceTask`。让 jobImpl 持有这些 task 对象。`JobImpl` 状态从 `NEW` 变为 `INIT`。然后直接调用 `startJobs` 启动job，发送发送`JobEventType.JOB_START`事件。
2. `JobImpl`处理 `JobEventType.JOB_START` 事件, 状态变为 `SETUP`。记录历史事件，并设置输出`OutputCommitter#setupJob`。完成后发出事件 `JobEventType.JOB_SETUP_COMPLETED`，`JobImpl`的状态变为`RUNNING`，触发hook 调用 `scheduleTasks`函数，发出 `TaskEventType.T_SCHEDULE` 事件。
3. `TaskImpl` 处理`TaskEventType.T_SCHEDULE` 事件，状态从`NEW`变为`SCHEDULED`。hook函数会实例化一个 `TaskAttemptImpl`对象并持有它，然后发送 `TaskAttemptEventType.TA_SCHEDULE`事件。
4. `TaskAttemptImpl`处理`TaskAttemptEventType.TA_SCHEDULE`事件，状态从`NEW`变为`UNASSIGNED`。hook会发送`ContainerAllocator.EventType.CONTAINER_REQ`事件，表示请求container。
5. `RMContainerAllocator` 会处理`ContainerAllocator.EventType.CONTAINER_REQ`事件，异步处理这个事件，把这个事件转化为请求（向RM申请资源的请求）。然后又是异步处理，RMContainerAllocator 会启动一个线程，发送心跳 heartbeat，去向RM请求container。`RMContainerAllocator#heartbeat` 方法会先获取已分配到的container资源，把这些container 分配给 taskAttempt，并发送`TaskAttemptEventType.TA_ASSIGNED`事件。没分配调的container 释放掉。
6. `TaskAttemptImpl`处理`TaskAttemptEventType.TA_ASSIGNED`事件，状态从`UNASSIGNED`，变为`ASSIGNED`。然后这个`TaskAttemptImpl`持有分配给它的 container，创建`ContainerLauncherContext`对象，里面填充了启动container需要的信息。注册TaskAttemptListener，管理各个任务的心跳信息，探测任务是否还活着。发送`ContainerLauncher.EventType.CONTAINER_REMOTE_LAUNCH`事件。
7. `ContainerLauncherImpl` **异步**处理 `ContainerLauncher.EventType.CONTAINER_REMOTE_LAUNCH`事件。
8. 在`ContainerLauncherImpl#launch` 方法里面，先获取或生成一个 RPC 客户端代理，RPC调用`startContainers`方法，要求启动container。发送`TaskAttemptEventType.TA_CONTAINER_LAUNCHED`事件。
9. `TaskAttemptImpl`处理`TaskAttemptEventType.TA_CONTAINER_LAUNCHED`事件，状态从`ASSIGNED`到`RUNNING`。hook方法里面， 会注册`TaskAttemptListener`监听器来监控这个taskAttempt。设置 `taskAttempt.remoteTesk = null`。发送`TaskEventType.T_ATTEMPT_LAUNCHED`事件。
10. `TaskImpl` 处理 `TaskEventType.T_ATTEMPT_LAUNCHED`事件，状态从 `SCHEDULED` 到 `RUNNING`。

----------

> 第8步中，在AM的环境中，`ContainerLauncherImpl#launch` 方法里面获取 RPC 调用`startContainers`，要求启动container。
> 
> NM中的`ContainerManagerImpl`作为RPC协议`ContainerManagerImpl`的server端，接收这个请求并处理。在`startContainers`方法里面调用`startContainerInternal`来启动container。
> 
> 在NM的中，先资源本地化，到`ContainersLauncher`接收`LAUNCH_CONTAINER`事件，异步实例化一个`ContainerLaunch`对象来启动任务。会调用`ContainerLaunch#call`方法。
> 
> `ContainerLaunch#call`方法详解：从 RPC 请求中获取 `ContainerLaunchContext`对象，从中获取执行命令cmd并本地环境化，创建本地目录，放入执行命令脚本，所需要的资源(在前面步骤已经从hdfs下载到本地)。发送`ContainerEventType.CONTAINER_LAUNCHED`事件。调用`ContainerExecutor#activateContainer`方法active container，调用`ContainerExecutor#launchContainer`执行container里面的task，这是个阻塞方法，阻塞到container退出。正常结束，发送`ContainerEventType.CONTAINER_EXITED_WITH_SUCCESS`事件。
> 
> container中启动的是`YarnChild`类，在`main`方法里面生成 `TaskUmbilicalProtocol`协议的代理对象，RPC调用`getTask`获取`JvmTask`任务实例，从中拿出`Task`实例(mapTask或reduceTask)，创建这个 task 的运行配置conf，然后异步执行这个 task。后面的执行过程详见`MapTask`或`ReduceTask`。
> task 任务完成的时候，会进行一个 RPC 调用 `TaskUmbilicalProtocol#done`，AM的`TaskAttemptListenerImpl`作为服务器会处理这个请求。

----------

- n1：`TaskAttemptListenerImpl`接到`done`rpc请求，发送一个`TaskAttemptEventType.TA_DONE`事件。
- n2：后面的过程不说了。。。

需要注意的是：一个TaskImpl完成，并不代表所有的task已经完成，Job怎么知道所有的任务已经完成？？