# FairScheduler 排序算法 #

----------

### 一、概念介绍 ###

首先，了解这几个概念：

- 资源需求量：当前队列或者应用希望获得的资源的总量。
- 最小份额：队列的最小共享量在配置中指定。应用的最小共享量为0。
- 资源使用量：当前队列或者应用已经分配到的总资源。
- 权值：队列的权重值在配置中指定。
	
在开启`sizebasedweight`特性的情况下:

	应用的权重=（log2(资源需求量)）* 优先级 * 调整因子。
	优先级当前都是1，当应用运行超过5分钟，调整因子为3。

----------

### 二、排序算法 ###

排序只需了解对于两个比较体的比较算法，然后对返回值升序排序。这里的比较体是队列或应用。
不说什么比较体，暂且称为队列吧，当然这个算法同样应用与队列内部应用的排序。

#### 1. 是否饥饿，即是否满足最小需求 ####
首先，计算两个队列各自的

	资源使用量 < min(资源需求量,最小份额）

即是否饥饿。然后，饥饿的队列优先。

#### 2. 比较资源分配比 ####

对于两者都饥饿的情况下，需要计算资源分配比，结果小者优先。

	资源分配比=资源使用量/min（资源需求量，最小份额, 1）

当都不饥饿时，需要计算资源使用权值比，结果小者优先。

#### 3. 比较资源使用量权重比 ####

	资源使用权重比=资源使用量/权值

#### 4. 比较提交时间 ####
如果资源分配比或权值比相等，先提交的优先。

----------

### 三、比较器代码 ###

下面看看相关代码吧
队列内部的应用排序算法默认采用fair排序，即与队列的排序相同。

	  private static class FairShareComparator implements Comparator<Schedulable>,
	      Serializable {
	    private static final long serialVersionUID = 5564969375856699313L;
	
	    @Override
	    public int compare(Schedulable s1, Schedulable s2) {
	      double minShareRatio1, minShareRatio2;
	      double useToWeightRatio1, useToWeightRatio2;
	      //计算两个队列各自的资源使用量 < min(资源需求量,最小份额），即是否饥饿。
	      Resource minShare1 = Resources.min(RESOURCE_CALCULATOR, null,
	          s1.getMinShare(), s1.getDemand());
	      Resource minShare2 = Resources.min(RESOURCE_CALCULATOR, null,
	          s2.getMinShare(), s2.getDemand());
	      boolean s1Needy = Resources.lessThan(RESOURCE_CALCULATOR, null,
	          s1.getResourceUsage(), minShare1);
	      boolean s2Needy = Resources.lessThan(RESOURCE_CALCULATOR, null,
	          s2.getResourceUsage(), minShare2);
	      Resource one = Resources.createResource(1);
	      //计算资源分配比，分母不会小于1
	      minShareRatio1 = (double) s1.getResourceUsage().getMemory()
	          / Resources.max(RESOURCE_CALCULATOR, null, minShare1, one).getMemory();
	      minShareRatio2 = (double) s2.getResourceUsage().getMemory()
	          / Resources.max(RESOURCE_CALCULATOR, null, minShare2, one).getMemory();
	      //计算资源使用权值比
	      useToWeightRatio1 = s1.getResourceUsage().getMemory() /
	          s1.getWeights().getWeight(ResourceType.MEMORY);
	      useToWeightRatio2 = s2.getResourceUsage().getMemory() /
	          s2.getWeights().getWeight(ResourceType.MEMORY);
	      int res = 0;
	      //饥饿者优先
	      if (s1Needy && !s2Needy)
	        res = -1;
	      else if (s2Needy && !s1Needy)
	        res = 1;
	      else if (s1Needy && s2Needy)
	      //两者都饥饿的情况下，比较资源分配比
	        res = (int) Math.signum(minShareRatio1 - minShareRatio2);
	      else
	        // Neither schedulable is needy
	        //比较资源使用权值比
	        res = (int) Math.signum(useToWeightRatio1 - useToWeightRatio2);
	      if (res == 0) {
	        // Apps are tied in fairness ratio. Break the tie by submit time and job
	        // name to get a deterministic ordering, which is useful for unit tests.
	        res = (int) Math.signum(s1.getStartTime() - s2.getStartTime());
	        if (res == 0)
	        //这里是如果二者同时启动的，就按字典序比较名称
	          res = s1.getName().compareTo(s2.getName());
	      }
	      return res;
	    }
	  }

可以看出，前面可配置的几个参数中（最小份额和权值，其它的在运行过程中都是可变的），对排序结果影响的顺序是先最小份额，再权值。这些参数是配合着使用，还是只保留一个变量原则，还需要看应用的场景。

比如，你需要的是保证相对的公平，追求地位平等，当然也可以把他们的配置都做成一样的。但是这样却没有考虑到运行时的一些因素，如集群繁忙情况、每个队列的资源使用量以及需求量等都是可变因素。所以，最好是最小份额和权值配合着使用，可以遵循“谁愿意共享得越多，就可以获得更多的资源”的原则，即最小份额与权值成反比。

另外一种情况，你需要有一个等级分明、两级分化的环境，那就有人说了，怎么不直接用另一个调度器 Capacity Scheduler ？当然如果你不考虑它配置的苛刻“所有队列的容量之和应小于100”，它是可以满足的。而公平调度没有这个限制，无论多么不合理的配置都能够处理。好吧，说正题，这时最好统一最小份额配置，通过调节权值来体现两极分化（涉及到另外一个公平份额算法）。

----------

### 四、fair-scheduler.xml配置文件样例： ###

	<?xml version="1.0"?>

	<allocations>
	  <user name="jenkins">
	    <!-- Limit on running jobs for the user across all pools. If more
	      jobs than this are submitted, only the first <maxRunningJobs> will
	      be scheduled at any given time. Defaults to infinity or the
	      userMaxJobsDefault value set below. -->
	    <maxRunningJobs>1000</maxRunningJobs>
	  </user>
	  <userMaxAppsDefault>1000</userMaxAppsDefault>
	  <queue name="sls_queue_1">
	    <minResources>1024 mb, 1 vcores</minResources>
	    <schedulingMode>fair</schedulingMode>
	    <weight>0.25</weight>
	    <minSharePreemptionTimeout>2</minSharePreemptionTimeout>
	  </queue>
	  <queue name="sls_queue_2">
	    <minResources>1024 mb, 1 vcores</minResources>
	    <schedulingMode>fair</schedulingMode>
	    <weight>0.25</weight>
	    <minSharePreemptionTimeout>2</minSharePreemptionTimeout>
	  </queue>
	  <queue name="sls_queue_3">
	    <minResources>1024 mb, 1 vcores</minResources>
	    <weight>0.5</weight>
	    <schedulingMode>fair</schedulingMode>
	    <minSharePreemptionTimeout>2</minSharePreemptionTimeout>
	  </queue>
	</allocations>
