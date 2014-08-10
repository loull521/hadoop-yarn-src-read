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

