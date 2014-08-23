# YARN 客户端程序 #

## Client提交一个应用程序需要两个步骤 ##

1. Client通过 RPC 函数 `ApplicationClientProtocol#NewApplication` 从 `ResourceManager` 获取唯一的 application ID。
2. Client 通过 RPC 函数 `ApplicationClientProtocol#submitApplication` 将 AM 提交到 RM上。

		// 获取 application id
		ApplicationClientProtocol rmClient = 
				RPC.getProxy(ApplicationClientProtocol.class, 0, address, conf);
		GetNewApplicationRequest request = Records.newRecord(GetNewApplicationRequest.class);
		GetNewApplicationResponse response = rmClient.getNewApplication(request);
		ApplicationId appId = response.getApplicationId();
		
		// 发送 submitApplication 请求
		ApplicationSubmissionContext appContext = Records.newRecord(ApplicationSubmissionContext.class);
		appContext.setApplicationName("app name");
		ContainerLaunchContext amContainer = Records.newRecord(ContainerLaunchContext.class);
		amContainer.setLocalResources(new HashMap<String, LocalResource>());
		amContainer.setEnvironment(new HashMap<String, String>());
		appContext.setAMContainerSpec(amContainer);
		appContext.setApplicationId(appId);
		SubmitApplicationRequest submitApplicationRequest = Records.newRecord(SubmitApplicationRequest.class);
		submitApplicationRequest.setApplicationSubmissionContext(appContext);
		rmClient.submitApplication(submitApplicationRequest);

