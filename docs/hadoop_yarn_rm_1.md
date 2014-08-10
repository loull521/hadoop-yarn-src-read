# ResourceManager  #

## 一、RM 各个组件 ##

![](https://github.com/loull521/hadoop-yarn-src-read/raw/master/raw/pictures/rm/resource_manager.png)

### 1、客户端连接模块 ###

RM作业提交、管理功能

- ClientService
- AdminService

### 2、NM管理模块 ###

- `ResourceTrackerService`处理NM注册和心跳
- `NMLivelinessMonitor`监控NM是否活着
- `NodesListManager`提供NM黑白名单

### 3、ApplicationMaster管理模块 ###

- `ApplicationMasterService`处理来自AM的请求，包括注册和心跳
- `AMLivelinessMonitor`监控AM是否活着
- `ApplicationMasterLauncher`与某个NodeManager通信，要求Nm启动某个程序的AM

### 4、Application管理模块 ###

- `RMAppManager`管理某个程序的启动和关闭
- `ApplicationACLsManager`管理程序访问权限，修改和查看权限
- `ContainerAllocationExpirer`当AM收到RM新分配的container后，必须在一定时间内启动该container，否则RM将回收它，这个过程由`ContainerAllocationExpirer`管理

### 5、资源分配模块 ###

- `ResourceScheduler`

### 6、4种状态机 ###

> 这4种状态机的实例并没有直接放在RM中，而是在RM的子组件里面。

- `RMApp`：维护一个应用程序Application的整个运行周期。RMApp的实例在RMApplicationManager中。
- `RMAppAttempt`：Application的运行实例，`RMAppAttempt`维护了一次尝试运行实例的运行周期。`RMAppAttempt`实例放在RMApp维护的运行实例集合里。
- `RMNode`维护了NM的生命周期。RMNode的实例对象在ResourceTrackerService里。
- `RMContainer`维护了container的运行周期。（暂时不确定是否支持重用）

## 二、RM通信的模块和对应的协议 ##

![](https://github.com/loull521/hadoop-yarn-src-read/raw/master/raw/pictures/rm/rm_event_workflow.jpg)

#### ClientRMProtocol、RMAdminProtocol ####

- server：ClientService、AdminService
- client：Client

#### ResourceTracker ####

- server：ResourceTrackerService
- client：NodeManager

#### ApplicationMasterProtocol ####

- server：ApplicationMasterService
- client：ApplicationMaster

## 三、RM内部组件的状态机 ##

### 1、RMApp状态机 ###

![](https://github.com/loull521/hadoop-yarn-src-read/raw/master/raw/pictures/rm/RMApp.png)

----------

### 2、RMAppAttempt状态机 ###

![](https://github.com/loull521/hadoop-yarn-src-read/raw/master/raw/pictures/rm/RMAppAttempt.png)

----------

### 3、RMNode状态机 ###

![](https://github.com/loull521/hadoop-yarn-src-read/raw/master/raw/pictures/rm/RMNode.png)

----------

### 4、RMContainer状态机 ###

![](https://github.com/loull521/hadoop-yarn-src-read/raw/master/raw/pictures/rm/RMContainer.png)

## 四、启动Application ##

![](https://github.com/loull521/hadoop-yarn-src-read/raw/master/raw/pictures/rm/rm_start_app.png)

> 说明：
> 
> 蓝线是事件异步调用
> 
> 红线是函数调用
> 
> 绿线是RPC远程调用

> **解释：** 
> 
> 1、如果不做额外说明，这里的异步事件调用都是通过RM的AsyncDispatcher调度的。
> 
> 2、基本上耗时的IO操作都启动其他线程进行异步操作。比如RMStateStore的存储事件，还有ResourceScheduler的调度事件。
> 
> 3、第15步，`AMLauncher`作为`ContainerManagementProtocol`协议的客户端，与NM通信，要求启动container。这点上有点奇怪。


### 1、大致过程 ###

1. 客户端提交作业后，初始化相关的RMAppImpl、 RMAppAttemptImpl 后直接提交到 Scheduler 组件中。RMAppImpl状态到了ACCEPTTED;RMAppAttempt状态到了SCHEDULED；container的状态是ALLOCATED。对应图中的 `1~10` 。
2. NM向RM的ResourceTrackerService发出心跳，RM回复要求一个container，触发状态改变。RMApp仍在ACCEPTTED；RMAppAttempt状态到了LAUNCHED；container的状态是ACQUIRED。对应图中`11~16`
3. NM准备好了container，再次向RM发送心跳，触发状态改变。container的状态是RUNNING。对应图中`17`。
4. appMaster随后就向 RM 注册且向 ApplicationMasterService 申请资源。RMApp、RMAppAttempt状态都变为RUNNING。对应图中`19~20`。
5. appMaster 向 ApplicationMasterService 报告完成任务。没画在图中。

### 2、详细步骤分析 ###

1.	RM的组件ClientRMService收到来自客户端的submitApplication请求，函数调用RMAppManager的submitApplication方法。
2.	RMAppManager提交一个START事件给RM的中央异步调度器（rmdispatcher），调度器把这个事件交给ApplicationEventDispatcher处理。ApplicationEventDispatcher根据ApplicationId找到对应的RMAppImpl状态机，然后给RMAppImpl处理。（后面我把这个过程简化，直接把事件交给相应的状态机，这样图上会更清晰。如果不额外说明，默认抛出的事件都是由rmdispatcher处理，并交给对应的事件处理器。并用rmdispatcher代表RM的中央异步处理器）。
3.	RMAppImpl本身是个状态机，收到一个@START事件，状态从NEW变为NEW_SAVEING，状态转移触发的hook函数调用RMStateStore，让它存储状态。
4.	RMStateStore抛出一个@STORE_APP事件给自己的中央调度器（中央调度器都会有自己的一个线程，循环处理事件队列），调度器又把这个事件交给RMStateStore内部类ForwardingEventHandler处理。具体的存储过程交给RMStateStore去做，YARN建议ZKStateStore。在RMStateStore饶了一圈，就是要把状态存储这份工作异步处理，而且使用的自己的中央异步调度器，而不是RM的。最后抛出一个事件@APP_NEW_SAVED给RMAppImpl。
5.	收到事件后，RMAppImpl的状态从NEW_SAVING到SUBMITTED，对应的hook抛出一个@SchedulerEventType.APP_ADDED调度事件。
6.	ResourceManager. SchedulerEventDispatcher会处理这个事件。SchedulerEventDispatcher内部有一个线程，随RM一起启动。SchedulerEventHandler把这个事件放到内部的阻塞队列，内部线程会循环处理事件队列，具体处理过程交给ResourceScheduler的子类去做。YARN默认的调度器是CapacityScheduler。1、先是检查queue节点是否装备好，如果准备好，就把这个appId挂到queue叶子节点上；2、创建一个SchedulerApplication对象（跟踪application），把这个对象添加到applications集合中，后面会被拿出来用；3、抛出一个事件RMAppEventType.APP_ACCEPTED。调度器有很复杂的逻辑，后面说，这里的正常逻辑就是抛出一个事件RMAppEventType.APP_ACCEPTED。
7.	RMAppImpl接收到这个事件后，状态从SUBMITTED到ACCEPTTED，对应的hook创建一个新的appAttempt，并把这个appAttempt添加到RMAppImpl维护的attemps集合中。完成后抛出一个RMAppAttemptEventType.START事件。
8.	RMAppAttempt处理这个事件。是根据ApplicationId和ApplicationAttempId找到的对应appAttempt。把这个实例的ID appAttemptId注册到ApplicationMasterServices。抛出一个事件SchedulerEventType.APP_ATTEMPT_ADDED。状态从NEW变为SUBMITTED。
9.	ResourceManager. SchedulerEventDispatcher接到这个事件，又交给CapacityScheduler去处理。（下次调度事件我就直接转给CapacityScheduler了）。创建一个FiCaSchedulerApp对象（跟踪attempt运行情况），并把它设置为当前的app的运行实例。最后抛出RMAppAttemptEventType.ATTEMPT_ADDED事件。
10.	RMAppAttempImpl处理这个事件。由于是第一次运行app，还没有分配AM，所以这里返回状态是SCHEDULED，而不是LAUNCHED_UNMANAGED_SAVING，也就是状态从SUBMITTED到SCHEDULED。对应的hook会调用CapacityScheduler#allocate方法，CapacityScheduler会把这个app保存到reserved集合中，等待NM的下一次心跳，返回信息中告诉NM为这个app启动一个container。
11.	NodeManager发送heartbeat到RM的ResourceTrackerService，ResourceTrackerService抛出一个RMNodeEventType.STATUS_UPDATE事件，RMNodeImpl处理这个事件，然后抛出一个SchedulerEventType.NODE_UPDATE事件，CapacityScheduler处理这个事件，发送一个RMContainerEventType.START事件。
12.	RMContainerImpl收到这个事件，状态中NEW变为ALLOCATED，抛出一个RMAppAttemptEventType.CONTAINER_ALLOCATED事件。
13.	RMAppAttemptImpl处理这个事件，hook再次调用CapacityScheduler#allocate方法，这次一定能获得至少一个container。（返回container之前抛出会抛出RMContainerEventType.ACQUIRED事件，这个事件被RMContainerImpl处理，hook会向ContainerAllocationExpirer注册监控这个container，然后抛出RMAppAttemptEventType.CONTAINER_ACQUIRED事件，RMAppAttemptImpl收到这个事件没有后续处理。RMContainerImpl从ALLOCATED到ACQUIRED。）把这个container设置为appAttempt的masterContainer，调用RMStateStore保存当前状态。RMAppAttemptImpl状态从SCHEDULED到ALLOCATED_SAVING。
14.	RMStateStore保存完毕后，抛出RMAppAttemptEventType.ATTEMPT_NEW_SAVED事件，RMAppAttempt处理这个事件，hook抛出一个AMLauncherEventType.LAUNCH事件。RMAppAttempt状态从ALLOCATED_SAVING变为ALLOCATED。
15.	ApplicationMasterLauncher处理这个事件，把这个事件封装成AMLauncher对象（是一个Runnable对象）放到阻塞队列里面，内部线程池启动AMLauncher线程去处理（又是异步操作）。AMLauncher发出startContainers(RPC请求)要求启动container，阻塞直到收到返回结果。这个过程中会与对应NM通信，然后启动ApplicationMaster。完成后抛出一个RMAppAttemptEventType.LAUNCHED事件。
16.	RMAppAttemptImpl处理这个事件，hook函数调用attemptLaunched方法，注册appAttempt到AMLivelinessMonitor。RMAppAttemptImpl状态从ALLOCATED到LAUNCHED。
17.	NM通过心跳机制汇报ApplicationMaster所在的Container已经成功启动，RM的ResourceTrackerService收到消息后，发出一个RMNodeEventType.STATUS_UPDATE事件，RMNodeImpl处理这个事件，发出SchedulerEventType.NODE_UPDATE事件，然后这个事件CapacityScheduler处理，发出RMContainerEventType.LAUNCHED事件。
18.	RMContainerImpl处理RMContainerEventType.LAUNCHED事件，从ContainerAllocationExpirer的监控列表中把这个RMContainerImpl移除。RMContainerImpl从状态LAUNCHED变为RUNNING。
19.	启动的ApplicationMaster通过RPC函数ApplicationMasterProtocol#registerApplicationMaster向RM注册，在RM中的ApplicationMasterService收到请求后，发出一个RMAppAttemptEventType.REGISTERED事件。RMAppAttemptImpl处理事件，hook先保存AM的基本信息，比如host、port等，然后发出一个RMAppEventType.ATTEMPT_REGISTERED事件。RMAppAttemptImpl状态从LAUNCHED到RUNNING。
20.	RMAppImpl处理RMAppEventType.ATTEMPT_REGISTERED事件，状态从ACCETPPED到RUNNING。

----------

### 3、RM的中央异步调度器rmdispatcher调度事件 ###

上图中对使用rmdispatcher的事件调度都简化了，下图表示第三步的正常流程：

![](https://github.com/loull521/hadoop-yarn-src-read/raw/master/raw/pictures/rm/rmdispatcher_demo.png)


## 五、申请与分配Container ##

整个过程分为两个阶段，循环：

1. ApplicationMaster汇报资源需求并领取已经分配到的资源
2. NodeManager向RM汇报各个container运行状态。如果RM发现这个NM上有空闲资源，进行一次分配，并将分配的资源保存到对应的数据结构(Allocation实例)，等待下一次ApplicationMaster发送心跳时获取。