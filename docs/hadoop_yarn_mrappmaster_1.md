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

![](https://github.com/loull521/hadoop-yarn-src-read/raw/master/raw/pictures/am/MRJobImpl.png)

----------

### 2、TaskImpl状态机 ###

![](https://github.com/loull521/hadoop-yarn-src-read/raw/master/raw/pictures/am/MRTaskImpl.png)

----------

### 3、TaskAttemptImpl状态机 ###

![](https://github.com/loull521/hadoop-yarn-src-read/raw/master/raw/pictures/am/MRJobAttemptImpl.png)

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

1. `MRAppMaster`启动的最后发出 `JobEventType.JOB_INIT` 事件，然后直接同步调用处理器去处理这个事件(非异步)。
2. `JobImpl`处理这个事件。初始化 job 信息，并且创建 `mapTask` 和 `reduceTask`。让 jobImpl 持有这些 task。
3. 