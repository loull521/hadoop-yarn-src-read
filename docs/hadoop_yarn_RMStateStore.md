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



----------

### 三、什么时候存储状态 ###

