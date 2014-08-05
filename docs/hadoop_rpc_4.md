# Hadoop Yarn源码阅读 -- hadoop RPC框架 server(四)#

## 一、server总体框架 ##

Server端主要用了Reactor模式，都是使用NIO，这两个细节都不细讲了，看图。

![](https://raw.githubusercontent.com/loull521/hadoop-yarn-src-read/master/raw/pictures/client-server.jpg)

----------

Reactor模式：

![](https://raw.githubusercontent.com/loull521/hadoop-yarn-src-read/master/raw/pictures/reactor.jpg)

----------

Hadoop RPC server：

![](https://raw.githubusercontent.com/loull521/hadoop-yarn-src-read/master/raw/pictures/RPC_server.jpg)

## 二、Server实现的一些细节 ##

#### Server#run() ####

	  public synchronized void start() {
	    responder.start();
	    listener.start();
	    handlers = new Handler[handlerCount];
	    
	    for (int i = 0; i < handlerCount; i++) {
	      handlers[i] = new Handler(i);
	      handlers[i].start();
	    }
	  }

启动Response、Listener、Handlers线程。

----------

#### Server.Listener#Listener()构造方法： ####

	readers = new Reader[readThreads];
	for (int i = 0; i < readThreads; i++) {
	  Reader reader = new Reader(
	       "Socket Reader #" + (i + 1) + " for port " + port);
	  readers[i] = reader;
	  reader.start();//启动readers
	}
	acceptChannel.register(selector, SelectionKey.OP_ACCEPT);


配置SocketChannel，绑定address，port，创建selector，然后启动readers线程：

----------

#### Server.Listener#run(): ####

	public void run() {
      SERVER.set(Server.this);
      connectionManager.startIdleScan();//启动轮询，关闭空闲一定时间的Connection
      while (running) {//循环监听
        SelectionKey key = null;
          getSelector().select();//select() accept请求
			。。。
          doAccept(key);//接受连接请求，创建一个read线程去读这个连接的数据
          closeCurrentConnection(key, e);
          connectionManager.closeIdle(true);
       }
        // close all connections
        connectionManager.stopIdleScan();//////////////////////
        connectionManager.closeAll();
	}

----------

#### Server.Listener#doAccept(): ####

循环监听到channel，channel注册获取Connection，把key附给channel，然后把Connection添加到某个reader的阻塞队列里面。

	channel = server.accept(); 
	//从reader池中取出一个reader
	Reader reader = getReader();
	//把Connection注册到	ConnectionManager，让CM去管理，会定期close空闲的Connection
	Connection c = connectionManager.register(channel);
	// so closeCurrentConnection can get the object
	key.attach(c);  
	//添加到reader的阻塞队列，监听这个连接的OP_READ
	reader.addConnection(c);

----------

#### Server.Listener.Reader#doRunLoop(): ####

一直循环,从阻塞队列中取得Connection，nio方式监听这个Connection。每监听到一个`SelectionKey.OP_READ`就调用一次`doRead(key)`。

----------

#### Server.Listener#doRead(key) ####

	Connection c = (Connection)key.attachment();//拿出Connection
    c.setLastContact(Time.now());//刷新时间，防止被close
	count = c.readAndProcess();//connection调用这个方法
    if (count < 0) { //关闭这条连接,看看是什么原因导致count<0
        closeConnection(c);
        c = null;
    }
    else {//保持对这个Connection的监听
        c.setLastContact(Time.now());
    }

这里的readAndProcess()方法是要重点解释的。

## 三、Server.Connection#readAndProcess()处理过程 ##

	“hrpc”			4字节
	Version 		1字节，当前版本9
	ServiceClass 	1字节  默认是0，当前还没用上
	AuthProtocol 	1字节

	length			4字节，int类型
	IpcConnectionContextProto	4字节

	Length 			4字节，表示Rpc请求长度，为下面两项之和
	RpcRequestHeader	，包括callId，retry等信息
	RpcRequest

前4项是Connection header。中间2项Connection context。这6项可以合称handshake握手。

后3个是RPC Request。

#### header ####

- 如果前四个字节不是“hrpc ”，返回错误信息。
- 如果version != 9，返回版本不一致，如果version在3~8，会提示客户端使用旧版本的RPC。
- AuthProtocol==0，不验证用户身份，否则验证。

#### RPC Request ####

- `RpcRequestHeader`包括callId，retry等信息
- `RpcRequest`是函数调用请求

> 注意：同一个连接下(clientID,protocol一致),不管多少个RPC请求，前面4项和RpcRequestHeader只会读取到一次。从第二次RPC请求开始，只有length和RpcRequest。

----------

贴上这个方法的源码和注释：

	public int readAndProcess()
	        throws WrappedRpcServerException, IOException, InterruptedException {
	      while (true) {
	        /* Read at most one RPC. If the header is not read completely yet
	         * then iterate until we read first RPC or until there is no data left.
	         */    
	        int count = -1;
	        if (dataLengthBuffer.remaining() > 0) {//dataLengthBuffer应该有4个字节大小，true
	        	//读取channel的4个字节,连接建立之后，第一次获得的数据是“hrpc”,后面得到的是data的数据长度
	          count = channelRead(channel, dataLengthBuffer); 
	          if (count < 0 || dataLengthBuffer.remaining() > 0) 
	            return count;
	        }
	        
	        //Connection刚创建的时候connectionHeaderRead肯定是null
	        if (!connectionHeaderRead) {//读连接的前面几个字节，要确定是RPC请求
	          //Every connection is expected to send the header.
	          if (connectionHeaderBuf == null) {//分配3个字节的buffer
	            connectionHeaderBuf = ByteBuffer.allocate(3);
	          }
	          //读取channel3个字节
	          count = channelRead(channel, connectionHeaderBuf);
	          if (count < 0 || connectionHeaderBuf.remaining() > 0) {
	        	  //如果channel中没有数据，返回-1
	            return count;
	          }
	          //TODO 第5个字节是version，serviceClass是什么东西？？
	          int version = connectionHeaderBuf.get(0);
	          // TODO we should add handler for service class later
	          this.setServiceClass(connectionHeaderBuf.get(1));
	          dataLengthBuffer.flip();
	          
	          // Check if it looks like the user is hitting an IPC port
	          // with an HTTP GET - this is a common error, so we can
	          // send back a simple string indicating as much.
	          if (HTTP_GET_BYTES.equals(dataLengthBuffer)) {
	            setupHttpRequestOnIpcPortResponse();
	            return -1;
	          }
	          
	          if (!RpcConstants.HEADER.equals(dataLengthBuffer)//这里dataLengthBuffer应该是"hrpc"
	              || version != CURRENT_VERSION) {//HEADER也是4个字节的！！！
	            //Warning is ok since this is not supposed to happen.
	            LOG.warn("Incorrect header or version mismatch from " + 
	                     hostAddress + ":" + remotePort +
	                     " got version " + version + 
	                     " expected version " + CURRENT_VERSION);
	            setupBadVersionResponse(version);
	            return -1;
	          }
	          
	          // this may switch us into SIMPLE
	          authProtocol = initializeAuthContext(connectionHeaderBuf.get(2));          
	          
	          dataLengthBuffer.clear();//清空
	          connectionHeaderBuf = null;
	          connectionHeaderRead = true;//表示已经读取完头部
	          continue;//清空buffer并跳过这轮循环，这时Connection header已经读取
	        }

	        //读取length
	        if (data == null) {
	          dataLengthBuffer.flip();//这里dataLengthBuffer是要读取的数据data的长度
	          dataLength = dataLengthBuffer.getInt();
	          checkDataLength(dataLength);
	          data = ByteBuffer.allocate(dataLength);
	        }

	        //读取length长度的数据
	        count = channelRead(channel, data);
	        
	        if (data.remaining() == 0) {//表示争取读取dataLength长度的数据
	          dataLengthBuffer.clear();//dataLengthBuffer清空
	          data.flip();
	          //connectionContextRead一开始为false，一旦改成true之后就一直是true。
	          //说明不管多少次请求，isHeaderReader只有一次是false。
	          boolean isHeaderRead = connectionContextRead;
	          processOneRpc(data.array());//第一次读connectionContext。之后读的就是RPC Request部分
	          data = null;
	          if (!isHeaderRead) {
	            continue;
	          }
	        } 
	        return count;
	      }
	    }

----------

结束语：

上面几张图片取自《Hadoop技术内幕》