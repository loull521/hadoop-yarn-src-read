# CapacityScheduler 资源抢占策略 #

首先要说，`CapacityScheduler`抢占策略的实现和`FairScheduler`抢占策略的实现机制不一样。不仅是策略不一样，在YARN里面的策略实现机制也不一样。也就是说适用`CapacityScheduler`的策略policy不能给`FairScheduler`使用，因为它们没有针对一样的接口。

要启动 CapacityScheduler 资源抢占，要修改配置文件，默认是不开启抢占策略。

	1. 设置启动Monitor
	YarnConfiguration.RM_SCHEDULER_ENABLE_MONITORS
	2. 设置Monitor类：SchedulingMonitor
	YarnConfiguration.DEFAULT_RM_SCHEDULER_ENABLE_MONITORS
	3. 设置抢占策略Policy：ProportionalCapacityPreemptionPolicy
	YarnConfiguration.RM_SCHEDULER_MONITOR_POLICIES

针对`CapacityScheduler`的抢占策略必须实现`SchedulingEditPolicy`接口。
`ProportionalCapacityPreemptionPolicy`实现了`SchedulingEditPolicy`接口。
而监控实现的是否抢占的是`SchedulingMonitor`类。

整理下：

1. `SchedulingEditPolicy`：`CapacityScheduler`的抢占策略必须实现的接口。
2. `SchedulingMonitor`：监控抢占的线程。
3. `ProportionalCapacityPreemptionPolicy`：实现`SchedulingEditPolicy`接口，YARN提供给`CapacityScheduler`唯一的一个抢占策略。

RM里面初始化抢占策略

    protected void createPolicyMonitors() {
      //添加调度策略，默认配置下是非抢占的。如果配置成抢占的，抢占policy封装到SchedulingMonitor中，然后添加到active services列表
      if (scheduler instanceof PreemptableResourceScheduler
          && conf.getBoolean(YarnConfiguration.RM_SCHEDULER_ENABLE_MONITORS,
          YarnConfiguration.DEFAULT_RM_SCHEDULER_ENABLE_MONITORS)) {
    	  //这儿是针对CapacityScheduler的，因为只有它实现了PreemptableResourceScheduler接口。当然也可以自己实现
        List<SchedulingEditPolicy> policies = conf.getInstances(
            YarnConfiguration.RM_SCHEDULER_MONITOR_POLICIES,
            SchedulingEditPolicy.class);
        if (policies.size() > 0) {
          rmDispatcher.register(ContainerPreemptEventType.class,
              new RMContainerPreemptEventDispatcher(
                  (PreemptableResourceScheduler) scheduler));
          for (SchedulingEditPolicy policy : policies) {
            policy.init(conf, rmContext.getDispatcher().getEventHandler(),
                (PreemptableResourceScheduler) scheduler);
            // periodically check whether we need to take action to guarantee
            // constraints
            SchedulingMonitor mon = new SchedulingMonitor(policy);
            addService(mon);
          }
        }
      }
    }

