# Hadoop Yarn源码阅读 -- hadoop RPC框架Client(三)#

我看的是Hadoop-2.4.1的源代码。

首先，我们先写一个demo来看看怎么使用hadoop RPC框架：

	import java.io.IOException;
	import java.net.InetSocketAddress;
	
	import org.apache.hadoop.conf.Configuration;
	import org.apache.hadoop.ipc.ProtocolSignature;
	import org.apache.hadoop.ipc.RPC;
	import org.apache.hadoop.ipc.Server;
	import org.apache.hadoop.ipc.VersionedProtocol;
	import org.apache.hadoop.net.NetUtils;
	
	public class RPCTest2 {
		
		private static final String ADDRESS = "0.0.0.0";
		
		private static Configuration conf;
		
		public void setupConf() {
			conf = new Configuration();
		}
		
		public interface LoullProtocol extends VersionedProtocol {
			public static final long versionID = 2L;
			int add(int a, int b) throws IOException;
			String getName() throws IOException;
		}
		
		public class LoullImpl implements LoullProtocol {
			@Override
			public long getProtocolVersion(String protocol, long clientVersion)
					throws IOException {
				return LoullProtocol.versionID;
			}
	
			@Override
			public ProtocolSignature getProtocolSignature(String protocol,
					long clientVersion, int clientMethodsHash) throws IOException {
				return new ProtocolSignature(LoullProtocol.versionID, null);
			}
	
			@Override
			public int add(int a, int b) throws IOException {
				return a + b;
			}
	
			@Override
			public String getName() throws IOException {
				return "loull, you are so handsome!";
			}
		}
		
		private void testRpcCalls(Configuration conf) throws IOException {
			Server server = new RPC.Builder(conf).setProtocol(LoullProtocol.class)
					.setInstance(new LoullImpl()).setBindAddress(ADDRESS).setPort(0).build();
			server.start();
			
			InetSocketAddress addr = NetUtils.getConnectAddress(server);
			LoullProtocol proxy = RPC.getProxy(LoullProtocol.class, LoullProtocol.versionID, addr, conf);
			System.out.println("call add: " + proxy.add(1, 10));
			System.out.println("call getName: " + proxy.getName());
		}
	
		public static void main(String[] args) {
			RPCTest2 rpcTest = new RPCTest2();
			rpcTest.setupConf();
			try {
				rpcTest.testRpcCalls(conf);
			} catch (IOException e) {
				e.printStackTrace();
			}
		}
	}



## 一、Client客户端发起RPC调用 ##

### 1、先从客户端开始，客户端代理对象proxy的生成 ###

	LoullProtocol proxy = RPC.getProxy(LoullProtocol.class, LoullProtocol.versionID, addr, conf);

`LoullProtocol`是协议接口，里面有client需要调用的方法。

查看`PRC#getProxy(...)`的代码栈：
	
	RPC#getProxy(LoullProtocol.class, LoullProtocol.versionID, addr, conf)
	RPC#getProtocolProxy(protocol, clientVersion, addr, conf).getProxy()
	RPC#getProtocolEngine(protocol,conf).getProxy(protocol, clientVersion, 
			addr, ticket, conf, factory, rpcTimeout, connectionRetryPolicy)
	WritableRpcEngine#getProxy(…)

我们这里以默认的WritableRpcEngine为例，也可以用配置成使用ProtobufRpcEngine。

可以看到是WritableRpcEngine实例化了协议protocol的proxy对象。

WritableRpcEngine#getProxy(…)

	T proxy = (T) Proxy.newProxyInstance(protocol.getClassLoader(), new Class[] { protocol },
		 new Invoker(protocol, addr, ticket, conf, factory, rpcTimeout));
	return new ProtocolProxy<T>(protocol, proxy, true);

到这里，我们生成了代理对象proxy。

----------

### 2、代理对象proxy进行一次RPC调用：proxy.add(1, 10) ###

每次RPC请求会调用`WritableRpcEngine#Invoker#invoke(Object proxy, Method method, Object[] args)`方法

`WritableRpcEngine.Invoker`的构造方法`Invoker(…)`和调用函数`invoke(…)`:

	this.remoteId = Client.ConnectionId.getConnectionId(address, protocol,ticket, rpcTimeout, conf);
	this.client = CLIENTS.getClient(conf, factory);
	......
	final Call call = createCall(rpcKind, rpcRequest);
	ObjectWritable value = (ObjectWritable)client.call(RPC.RpcKind.RPC_WRITABLE, 
		new Invocation(method, args), remoteId);

可以看到最后交给了`Client#call()`去处理了，看看这个方法：

	Connection connection = getConnection(remoteId, call, serviceClass); 	//(1)
	......
	connection.sendRpcRequest(call);										//(2)
	......
	return call.getRpcResponse();											//(3)

这三个是主要的方法：

1. 创建或从缓存中拿出连接connection，把请求call加到Connection里面叫calls的map里面。然后发送7个字节的ConnectionHeader，和ConnectionContext信息。最后启动Connection线程，开始轮询处理calls里面的请求。
2. 发送RPC请求。包括RpcRequestHeaderProto信息(如callId，retry等)，和rpcRequest请求内容(其实就是Invocation，是请求函数和参数信息)。
3. 返回RPC请求结果。


## 二、Client内部处理逻辑 ##

先看看Client类的关系图

![](https://raw.githubusercontent.com/loull521/hadoop-yarn-src-read/master/raw/pictures/client.call.jpg)

#### Client.ConnectionID ####

ConnectionId用一个三元组<remoteAddress, protocol, ticket>表示。唯一标示用特定的连接Connection。

- `ticket`：User and group information for Hadoop. This class wraps around a JAAS Subject and provides methods to determine the user's username and groups.
- `protocol`：要使用的协议
- `remoteAddress`：Remote address for the connection.


#### Client.Call ####

封装了一次请求的信息和返回的数据。

- `id`:唯一标识这个call
- `retry`
- `rpcRequest`
- `rpcResponse`：封装了请求返回信息
- `rpcKind: RPC.RpcKind`:枚举类型，2表示使用WritableRpcEngine，3表示你懂的

#### Client.Connection ####

这是个线程，读取response 和 notify callers。

每个Connection拥有一个socket和一个remote address。

这个socket上会有多个call通信。

- `remoteId: ConnectionId`
- `serviceClass: int`:service class for RPC，现在还没用上，可以用于验证head info是否改变了，如果改变了这次通信就失败了。
- `socket: Socket`
- `in: DataInputStream`
- `out: DataOutputStream`
- `connectionRetryPolicy: RetryPolicy`
- `calls: Hashtable<Integer,Call>`：保存callId和call的映射关系，从服务器端收到回复后，解析出callId，找到对应的call，保证请求正确返回。（多个call请求时，收到的回复可能乱序）

#### Client ####

- `callId: ThreadLocal<Integer>`
- `valueClass: Class<? extends Writable>`：返回结果的类型，比如ObjectWritable
- `running: AtomicBoolean`
- `socketFactory: SocketFactory`
- `clientId: byte[]`
- `call(param: Writable, address: InetSocketAddress): Writable`
- `connections: Hashtable<ConnectionId,Connection>`：保存了连接

## Client#call()处理流程 ##

### 主线程Caller线程： ###

![](https://raw.githubusercontent.com/loull521/hadoop-yarn-src-read/master/raw/pictures/client_caller.jpg)

可以看到getConnection方法里面，addCall方法在setupIOStream方法前面，官方解释是server可能正好很慢，建立连接会用很长时间，会使整个系统变慢。

----------

### Connection线程：也就是Receive线程，负责接收处理Server的response ###

![](https://raw.githubusercontent.com/loull521/hadoop-yarn-src-read/master/raw/pictures/client_conn.jpg)

waitForWork()不一定会阻塞连接线程，只要Connection的calls队列不为空，就不会阻塞。