# FairScheduler 公平资源共享算法 computeShares #

----------

### 一、为什么需要这个算法 ###

为了抢占的需要

FairScheduler为了公平地分配资源，某些队列需要抢回它被占用的资源。在开启资源抢占的特性的情况下，调度器可能会杀死部分运行中的容器，释放超额的资源。

#### 抢占的实现 ####

公平调度器启动的时候会建立一个UpdateThread的线程，负责计算公平资源量和进行资源抢占。其中，调度器使用了公平资源共享算法重新计算队列的公平资源量。

----------

### 二、资源权重比 和 公平资源量`FairShare`###

> 资源权重比=资源获得量 / 队列权重。
> 
> 每点权重能分配到的资源。
> 
> 知道了资源权重比，每个队列就可以根据自己的权值，知道自己能分配多少资源。

如果只是单纯地求一个资源权重比，可以直接相除。但是由于需要满足队列的资源分配满足最小共享量、最大资源量这些队列上下界的限制，权值资源比不能直接计算。

反过来，如果知道资源权重比，就可以计算出集群一共需要多少资源，而且，也可以计算出每个队列的公平资源量。

	某个队列的公平资源量FairShare = 资源权重比 * 队列权重

----------

### 三、算法 ###

利用下面公式计算出 资源权重比R

	TotalResource = Σ Min{ max(weight[k] * R, minShare[k]), demand[k] }   k=1..n   
	R：资源权重比
 
计算出每个队列的 公平资源量`FairShare`：

	Min{ max(weight * R, minShare), demand }
	里面的 max 保证最少的资源量。
	外面的 min 保证不超过最大限制，一般配置文件不设置demand，默认为无穷大。
	minShare就是配置文件配置的<minResources>1024 mb, 1 vcores</minResources>

如果一个队列或app 的资源 少于 `fareShare`，它的资源肯定不会被抢占。

如果一个队列或app 的资源 超过 `fareShare`，监控检测到需要资源抢占时，它的资源可能被抢占。

----------

### 四、抢占模型 ###

确定了各自的公平份额后，更新各自的资源需求。然后检查是否有需要抢占其他队列资源的队列，判断依据有两个：

	资源使用量 < min(最小份额，资源需求量) || 资源使用量 < min(公平份额，资源需求量)

条件满足时求两个差值的最大值作为需要抢占的资源量，累加起来得到集群需要抢占的资源总量，即需要释放的资源。

发生抢占：

- 只要需要抢占的资源总量大于0，就选出所有资源使用量超过公平份额的队列。
- 再把这些队列里的正在运行的Container按照priority从大到小和启动时间从大到小排序（优先级值越小，等级越高）。
- 最后对这些Container依次发出警告，并在超时后强制kill释放资源。这个过程每500毫秒进行一次。

----------

### 五、FairScheduler的使用建议 ###

队列的**最小共享量**（minShare，也就是配置的minResources）越大，在集群繁忙的时候分配到的资源就越多。但是，如果每个用户都将最小共享量设置到最大，不利于集群间的资源共享。建议，将队列愿意共享出来的内存大小和队列的权值挂钩。含义就是，你愿意共享得越多，在整体资源分配中就越能分得更多的资源。

----------

### 六、代码实现 ###

这个算法在`org.apache.hadoop.yarn.server.resourcemanager.scheduler.fair.policies.ComputeFairShares` 这个类里面实现。

	  public static void computeShares(
	      Collection<? extends Schedulable> schedulables, Resource totalResources,
	      ResourceType type) {
	    if (schedulables.isEmpty()) {
	      return;
	    }
	    // Find an upper bound on R that we can use in our binary search. We start
	    // at R = 1 and double it until we have either used all the resources or we
	    // have met all Schedulables' max shares.
	    int totalMaxShare = 0;
	    for (Schedulable sched : schedulables) {
	      int maxShare = getResourceValue(sched.getMaxShare(), type);
	      if (maxShare == Integer.MAX_VALUE) {
	        totalMaxShare = Integer.MAX_VALUE;
	        break;
	      } else {
	        totalMaxShare += maxShare;
	      }
	    }
	    int totalResource = Math.min(totalMaxShare,
	        getResourceValue(totalResources, type));//先计算总资源
	    
	    double rMax = 1.0;
	    while (resourceUsedWithWeightToResourceRatio(rMax, schedulables, type)
	        < totalResource) {
	      rMax *= 2.0;
	    }
	    // Perform the binary search for up to COMPUTE_FAIR_SHARES_ITERATIONS steps
	    double left = 0;
	    double right = rMax;
	    for (int i = 0; i < COMPUTE_FAIR_SHARES_ITERATIONS; i++) {
	      double mid = (left + right) / 2.0;
	      if (resourceUsedWithWeightToResourceRatio(mid, schedulables, type) <
	          totalResource) {
	        left = mid;
	      } else {
	        right = mid;
	      }
	    }
	    // Set the fair shares based on the value of R we've converged to
	    for (Schedulable sched : schedulables) {
	      setResourceValue(computeShare(sched, right, type), sched.getFairShare(), type);
	    }
	  }
	
	  /**
	   * Compute the resources that would be used given a weight-to-resource ratio
	   * w2rRatio, for use in the computeFairShares algorithm as described in #
	   */
	  private static int resourceUsedWithWeightToResourceRatio(double w2rRatio,
	      Collection<? extends Schedulable> schedulables, ResourceType type) {
	    int resourcesTaken = 0;
	    for (Schedulable sched : schedulables) {
	      int share = computeShare(sched, w2rRatio, type);
	      resourcesTaken += share;
	    }
	    return resourcesTaken;
	  }
	
	  /**
	   * Compute the resources assigned to a Schedulable given a particular
	   * weight-to-resource ratio w2rRatio.
	   */
	  private static int computeShare(Schedulable sched, double w2rRatio,
	      ResourceType type) {
	    double share = sched.getWeights().getWeight(type) * w2rRatio;
	    //权值*资源权值比
	    share = Math.max(share, getResourceValue(sched.getMinShare(), type));
	    share = Math.min(share, getResourceValue(sched.getMaxShare(), type));
	    //保证应得份额在最小份额与最大份额之间
	    return (int) share;
	  }
