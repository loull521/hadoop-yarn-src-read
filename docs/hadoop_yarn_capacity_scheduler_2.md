# CapacityScheduler #

----------

### 一、AM请求资源 或 RM给分配AM的container ###

AM资源请求，RM调用Scheduler的 `allocate` 方法

	public Allocation allocate(ApplicationAttemptId applicationAttemptId,
      List<ResourceRequest> ask, List<ContainerId> release, 
      List<String> blacklistAdditions, List<String> blacklistRemovals)

`ResourceRequest` Scheduler的角度看资源请求是一个五元组：

	priority
	hostName			host、rack、*
	Resource			
	numContainers			
	relaxLocality		是否松弛本地性

`allocate`方法里面调用了下面方法，在第一次调用allocate时，返回一个空的Allocation。

	application.updateResourceRequests(ask);

application是`FiCaSchedulerApp`类型，表示以`CapacityScheduler`视角看待appAttempt。在上面方法里面又调用了：
	
	appSchedulingInfo.updateResourceRequests(requests);

appSchedulingInfo 的类型是 `AppSchedulingInfo`，以`Scheduler`的角度看，跟踪所有分配给app 的信息。

更新请求代码分析：

	synchronized public void updateResourceRequests(
	      List<ResourceRequest> requests) {
	    
	    // Update resource requests
	    for (ResourceRequest request : requests) {
	      //遍历每个请求，appAttempt一次请求可能申请多种不同的container
	      Priority priority = request.getPriority();
	      String resourceName = request.getResourceName();
	      boolean updatePendingResources = false;
	
	      //requests：Map<Priority, Map<String, ResourceRequest>>
	      //requests：维护了这个appAttempt所有资源请求信息，不只是本次的request
	      Map<String, ResourceRequest> asks = this.requests.get(priority);
	
	      if (asks == null) {//说明这个优先级的请求是第一次
	        asks = new HashMap<String, ResourceRequest>();
	        this.requests.put(priority, asks);
	        this.priorities.add(priority);
	      } 
	
	      asks.put(resourceName, request);//跟新这个优先级的资源请求
	    }
	  }

----------

### 二、NM心跳 ###

Scheduler 处理 `NODE_UPDATE` 事件

    case NODE_UPDATE:
    {
      NodeUpdateSchedulerEvent nodeUpdatedEvent = (NodeUpdateSchedulerEvent)event;
      RMNode node = nodeUpdatedEvent.getRMNode();
      nodeUpdate(node);//更新节点信息
      if (!scheduleAsynchronously) {
        allocateContainersToNode(getNode(node.getNodeID()));
		//分配container，给提出请求的appAttempt分配container
      }
    }

进入`allocateContainersToNode(getNode(node.getNodeID()));`方法，调用：

	root.assignContainers(clusterResource, node);

root是队列树的跟节点，进入：

	  public synchronized CSAssignment assignContainers(
	      Resource clusterResource, FiCaSchedulerNode node) {
	    CSAssignment assignment = 
	        new CSAssignment(Resources.createResource(0, 0), NodeType.NODE_LOCAL);//NODE_LOCAL
	    
	    while (canAssign(clusterResource, node)) {//如果没有reserved container，而且剩余资源大于最小分配，则可以分配
	      
	      // Are we over maximum-capacity for this queue?
	      if (!assignToQueue(clusterResource)) {
	        break;
	      }
	      
	      // Schedule
	      CSAssignment assignedToChild = 
	          assignContainersToChildQueues(clusterResource, node);//子节点
	      assignment.setType(assignedToChild.getType());
	      
	      // Done if no child-queue assigned anything
	      if (Resources.greaterThan(
	              resourceCalculator, clusterResource, 
	              assignedToChild.getResource(), Resources.none())) {
	        // Track resource utilization for the parent-queue
	        allocateResource(clusterResource, assignedToChild.getResource());//分配资源，更新节点资源信息
	        
	        // Track resource utilization in this pass of the scheduler
	        Resources.addTo(assignment.getResource(), assignedToChild.getResource());
	      } else {
	        break;//如果这个节点不能再分配了，跳出循环
	      }
	
	      // Do not assign more than one container if this isn't the root queue
	      // or if we've already assigned an off-switch container
	      //如果不是根节点，或 分配了一个off-switch container，就跳出循环，不再继续给这个节点分配container
	      //也就是最多给这个节点分配一个off-switch container
	      if (!rootQueue || assignment.getType() == NodeType.OFF_SWITCH) {
	        break;
	      }
	    } 
	    return assignment;
	  }

先进入`CSAssignment assignedToChild = assignContainersToChildQueues(clusterResource, node);`看看：

	  synchronized CSAssignment assignContainersToChildQueues(Resource cluster, 
	      FiCaSchedulerNode node) {
	    CSAssignment assignment = 
	        new CSAssignment(Resources.createResource(0, 0), NodeType.NODE_LOCAL);
	
	    // Try to assign to most 'under-served' sub-queue
	    for (Iterator<CSQueue> iter=childQueues.iterator(); iter.hasNext();) {
	      CSQueue childQueue = iter.next();
	      assignment = childQueue.assignContainers(cluster, node);//递归调用，最后到LeafQueue节点的assignContainers方法
	      
	      // If we do assign, remove the queue and re-insert in-order to re-sort
	      if (Resources.greaterThan(
	              resourceCalculator, cluster, 
	              assignment.getResource(), Resources.none())) {
	        // Remove and re-insert to sort
	        iter.remove();//删除，从新添加，为了重新排序
	        childQueues.add(childQueue);
	        break;
	      }
	    } 
	    return assignment;
	  }

从这个两个方法可以看出，这个是递归调用，让子节点去分配container，最后是叶子节点LeafQueue去分配。

1. 从根节点rootQueue开始。如果node还有资源，当前ParentQueue还能分配，则让ParentQueue的子节点轮流去分配(资源利用率低的节点排序靠前)。
2. 递归让子节点去分配，最后让叶子节点LeafQueue去分配。
3. 叶子节点`LeafQueue`分配了之后，返回分配结果`CSAssignment`给父节点。
4. 父节点`ParentQueue`获得分配结果后，更新自身节点资源情况，重新排序子节点。并且退出循环，即不用让其他儿子节点去分配了，因为已经做出一次分配了。递归交给父节点做同样处理。


总结过程：
> 1、从根节点rootQueue开始，找到叶子节点LeafQueue，叶子节点找出一个app，给这个app分配container。一次只会分配一个container
> 
> 2、如果分配了之后，node上还能分配资源，而且之前的分配类型不是NodeType.OFF_SWITCH，重复 1 步骤。
> 
> 一次NODE_UPDATE的结果就是：找到队列、app、container请求(优先级、本地性),分配一个container。
> 
> 如果这次分配assignment的类型不是NodeType.OFF_SWITCH，就继续分配，直到心跳的node没有资源或分配类型是NodeType.OFF_SWITCH。
> 
> 过程中会伴随着 节点 CSQueue 的资源变化和队列之间的重新排序。