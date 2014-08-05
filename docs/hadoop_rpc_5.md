# Hadoop Yarn源码阅读 -- hadoop RPC框架 Version 2 和 Version 9 的兼容性(五)#

现在内部使用的hadoop RPC 版本是2，而hadoop-2.4.1的RPC版本已经是9了。本文描述若要两个版本相互兼容，需要修改的代码和大致的工作量。

所谓兼容，这里要做到的就是：

- version 2的client 发送的RPC请求，能被version 9的server接收、解析并正确处理返回。
- version 9的server 返回的请求信息，能被version 2的client解析。

# 一、hadoop2.4.1 RPC version 9 的请求数据格式 #

## 1、handshake握手 ##

### (1). 连接头Connection header ###

	+----------------------------------+
	|  "hrpc" 4 bytes                  |      
	+----------------------------------+
	|  Version (1 byte)                |
	+----------------------------------+
	|  Service Class (1 byte)          |
	+----------------------------------+
	|  AuthProtocol (1 byte)           |      
	+----------------------------------+

### (2). Connection context ###

	+----------------------------------+
	|  4 bytes length 				   |
	+----------------------------------+
	| IpcConnectionContextProto        | 这里的callId=-3
	+----------------------------------+

## 2、One RPC Request ##
	
	+----------------------------------+
	|  length (4 byte)                 |
	+----------------------------------+
	|  RpcRequestHeader                | 这里的callId>=0
	+----------------------------------+
	|  RpcRequest			           |      
	+----------------------------------+

### WritableRpcEngine 的 RpcRequest: ###

> 第三项RpcRequest，在WritableRpcEngine的格式：

	+----------------------------------+
	|  rpcVersion (int)                |      
	+----------------------------------+
	|  declaringClassProtocolName      |
	+----------------------------------+
	|  methodName			           |
	+----------------------------------+
	|  clientVersion		           |      
	+----------------------------------+
	|  clientMethodsHash 		       |
	+----------------------------------+
	|  parameterClasses.length (int)   |
	+----------------------------------+
	|  [parameters,parameterClasses	]  |
	+----------------------------------+


## 3、WritableRpcEngine 的 RpcResponse： ##

	+----------------------------------------------------------+
		int - Message Length
	+----------------------------------------------------------+
		Varint - length of RpcResponseHeaderProto
	+----------------------------------------------------------+
		protocol buffers object - RpcResponseHeaderProto
	+----------------------------------------------------------+
		Writable response value (length known by intial length)
	+----------------------------------------------------------+

# 二、hadoop RPC version 2 的 请求数据格式 #

## 1、handshake ##

	+----------------------------------+
	|  "hrpc" 4 bytes                  |      
	+----------------------------------+
	|  Version (1 byte)                |
	+----------------------------------+

## 2、One RPC Request： ##
	
	+----------------------------------+
	|  length (4 byte)                 |
	+----------------------------------+
	|  callId (4 byte)                 | 
	+----------------------------------+
	|  RpcRequest			           |      
	+----------------------------------+

### RpcRequest: ###

> 第三项RpcRequest，具体的数据格式

	+----------------------------------+
	|  methodName			           |
	+----------------------------------+
	|  parameterClasses.length (int)   |
	+----------------------------------+
	|  [parameters,parameterClasses]   |
	+----------------------------------+

## 3、RpcResponse： ##

	+----------------------------------------------------------+
		int - callId
	+----------------------------------------------------------+
		boolean - curisError
	+----------------------------------------------------------+
		methodName
	+----------------------------------------------------------+
		int - parameterClasses.length
	+----------------------------------------------------------+
		[parameters,parameterClasses] 
	+----------------------------------------------------------+

# 三、兼容性修改 #


> 尽量减少对现有代码的修改，非要修改的话，尽量修改客户端的代码。

### 1、对于Connection header ###

只需要在version 2的client里面多写2个字节。

修改Client#writeHeader()

    /* Write the header for each connection
     * Out is not synchronized because only the first thread does this.
     */
    private void writeHeader() throws IOException {
      out.write(Server.HEADER.array());
      out.write(Server.CURRENT_VERSION);
        //TODO loull 为了兼容版本9，这里要写两个字节，都为0
      //When there are more fields we can have ConnectionHeader Writable.
      DataOutputBuffer buf = new DataOutputBuffer();
      ObjectWritable.writeObject(buf, remoteId.getTicket(), 
                                 UserGroupInformation.class, conf);
      int bufLen = buf.getLength();
      out.writeInt(bufLen);
      out.write(buf.getData(), 0, bufLen);
    }

----------

### 2、对于Connection context ###

> 修改version 9 的服务器，在`Server#readAndProcess()`方法里面专门加一块version==2的处理逻辑，里面修改几个状态改变。同时添加一个方法，功能同`Server#processOneRpc()`一样，但对应version 2.

----------

### 3、RpcRequest和RpcResponse的格式修改 ###

> 虽然两个版本都是使用Writable方式序列化，但是序列化的内容有些不同，要修改的都是Invocation类。个人建议是创建一个RpcEngine的子类，几乎和WritableRpcEngine一样，重写Invocation类，改成和version 2一样的格式。

----------

# 四、工作量估计，修改的文件： #

1. version 2 的Client#writeHeader()
2. version 9 的Server#readAndProcess()和添加一个类似Server#processOnePrc()方法。
3. version 9，添加一个RpcEngine的子类，然后配置成使用自己的RpcEngine。
4. 少数的状态变量依赖，修改上面3项的时候能够知道需要注意那些依赖。

工作量大概3~5天。