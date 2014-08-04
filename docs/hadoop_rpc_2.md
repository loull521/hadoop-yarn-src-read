# Hadoop Yarn源码阅读 -- hadoop RPC框架 数据流规则(二)#

# 一、Hadoop RPC总体思想： #

定义一个接口，这个接口server和client共用。client使用`java.reflection proxy`类生成一个RPC接口的代理实现。

当client进行一次调用，比如`String ping(String msg)`，在代理类里面会：

1. 序列化方法的参数
2. 连接到RPC Server
3. 告诉服务器执行这个方法

服务器会：

1. 反序列化参数
2. 执行方法
3. 序列化结果
4. 发送回给client

Here is an example of a very simple Hadoop RPC call.

	package com.github.elazar.hadoop.examples;
	
	import org.apache.hadoop.conf.Configuration;
	import org.apache.hadoop.ipc.ProtocolInfo;
	import org.apache.hadoop.ipc.RPC;
	
	import java.io.IOException;
	import java.net.InetSocketAddress;
	
	/**
	 * Hello world!
	 *
	 */
	public class HadoopRPC
	{
	    @ProtocolInfo(protocolName = "ping", protocolVersion = 1)
	    public static interface PingProtocol  {
	        String ping();
	    }
	
	    public static class Ping implements PingProtocol {
	        public String ping() {
	            System.out.println("Server: ");
	            return "pong";
	        }
	    }
	
	    public static InetSocketAddress addr = new InetSocketAddress("localhost", 5121);
	
	    public static RPC.Server server() throws IOException {
	        final RPC.Server server = new RPC.Builder(new Configuration()).
	                setBindAddress(addr.getHostName()).
	                setPort(addr.getPort()).
	                setInstance(new Ping()).
	                setProtocol(PingProtocol.class).
	                build();
	        server.start();
	        return server;
	    }
	
	    public static void client() throws IOException {
	        final PingProtocol proxy = RPC.getProxy(PingProtocol.class, RPC.getProtocolVersion(PingProtocol.class),
	                addr, new Configuration());
	        System.out.println("Client: ping " + proxy.ping());
	    }
	
	    public static void main(String[] args ) throws IOException {
	        final String runThis = args.length > 0 ? args[0] : "";
	        if (runThis.equals("server")) {
	            server();
	        } else if (runThis.equals("client")) {
	            client();
	        } else {
	            final RPC.Server server = server();
	            client();
	            server.stop();
	        }
	    }
	}

Code from：[github](https://github.com/elazarl/hadoop_rpc_walktrhough/blob/d39e4438394b98edba16591707e97ea703a3a663/src/main/java/com/github/elazar/hadoop/examples/HadoopRPC.java#L16)

Note that currently, a production Hadoop RPC interface, must extend and implement the VersionedProtocol interface. It's used by ProtocolProxy.fetchServerMethods to make sure client and server protocol version match. We neglected this detail for the sake of simplicity.

----------

# 二、Hadoop RPC 具体协议 #

### RPC handshake ###

The RPC handshake starts with a [header](https://github.com/apache/hadoop-common/blob/release-2.1.0-beta-rc1/hadoop-common-project/hadoop-common/src/main/java/org/apache/hadoop/ipc/Client.java#L764):发送一个header表示RPC握手

	+----------------------------------+
	|  "hrpc" 4 bytes                  |      
	+----------------------------------+
	|  Version (1 byte)                |
	+----------------------------------+
	|  Service Class (1 byte)          |
	+----------------------------------+
	|  AuthProtocol (1 byte)           |      
	+----------------------------------+

- Version表示RPC版本，当前是9。
- ServiceClass默认是0，当前没什么作用。
- AuthProtocol决定是否使用SASL authentication ，如果等于0,表示使用simple authentication，否则表示要用SASL authentication认证。

----------

### connection context ###

然后是connection context。它是一个`makeIpcConnectionContext`生成的protocol buffer message `IpcConnectionContextProto`。这个context object 定义了目的地的**RPC protocol名字**(we defined it as "ping", using Java annotations in the example above)，还定义了调用这个protocol的**user**。这个context限制了长度为4个字节的Int。

	+-------------------------------+
	|  4 bytes length 				|
	+-------------------------------+
	| IpcConnectionContextProto     |
	+-------------------------------+




**> header发送完了之后，如果需要，client会启动一个SASL authentication，会发送一个专门的`post`(I'll cover authentication in a dedicated post)**。

----------

### RPC request ###

初始的握手已经完成，可以开始发送Request给Server了。

Format of a call on the wire:

- Length of rest below (1 + 2)
- `RpcRequestHeader` - is serialized Delimited hence contains length 当前用的是google protocol buffers object -- `RpcRequestHeaderProto`
- `RpcRequest`
- The payload header, `RpcRequestHeaderProto`, is a google Protocol Buffers object, hence serializable by Protocol Buffers. The main content of this header are callId, which is an identifier of the RPC request in the connection, and clientId, which is a UUID generated for the client. Negative callIds, are reserved for meta-RPC purposes, e.g., to handshake SASL method. 【负载头，用的是protocol buffer对象，主要内容包括callId，clientId(唯一定义一个client),负数callId保留为meta-RPC purposes。】

payload 本身就是一个method call的序列化表示，用RpcEngine来序列化和反序列化，默认是WritableRpcEngine。至于为什么混合使用两种序列化方法，官方解释是正在从Writable转到protocol buffer。

----------

### RPC server response ###

RPC server 返回一个类似的response：

	int - Message Length
	Varint - length of RpcResponseHeaderProto
	protocol buffers object - RpcResponseHeaderProto
	Writable response value (length known by intial length)

The RpcResponseHeaderProto, contains the callId, used to identify the client, an indicator whether or not the call was successful, and in case it wasn't, information about the error.

----------

### 超时处理 ###

The last detail of the RPC protocol is the ping message. If the RPC client times out waiting for input, the client will send it `0xFF_FF_FF_FF`, **probably to keep the connection alive**. The server knows to ignore such headers. This can be disabled by setting ipc.client.ping=false, and is controlled by the PingInputStream class.

----------

# 三、ping案例 #

Let's have a look at a real example. Let's take the simple ping RPC server in our example git repository hadoop_rpc_walktrhough.

First, we'll set a fake server that records client traffic, and then we'll clone and run the simple RPC client.

	$ nc -l 5121 >clientRpcCall &
	[1] 25269
	$ git clone https://github.com/elazarl/hadoop_rpc_walktrhough.git
	Cloning into 'hadoop_rpc_walktrhough'...
	remote: Counting objects: 41, done.
	remote: Compressing objects: 100% (27/27), done.
	remote: Total 41 (delta 4), reused 36 (delta 4)
	Unpacking objects: 100% (41/41), done.
	$ mvn -q exec:java -Dexec.mainClass=com.github.elazar.hadoop.examples.HadoopRPC -Dexec.args="client"
	2013-08-18 06:32:06 WARN  NativeCodeLoader:62 - Unable to load native-hadoop library for your platform... using builtin-java classes where applicable

Now, let's look at the annotated hexdump of the output: [hadoop_rpc_walktrhough](https://github.com/elazarl/hadoop_rpc_walktrhough/blob/d39e4438394b98edba16591707e97ea703a3a663/go_hadoop_rpc/main_test.go#L15)

	//h   r     p     c
	0x68, 0x72, 0x70, 0x63,
	// version, service class, AuthProtocol
	0x09, 0x00, 0x00,
	// size of next two size delimited protobuf objets:
	// RpcRequestHeader and IpcConnectionContext
	0x00, 0x00, 0x00, 0x32, // = 50
	// varint encoding of RpcRequestHeader length 
	0x1e, // = 30
	0x08, 0x02, 0x10, 0x00, 0x18, 0xfd, 0xff, 0xff, 0xff, 0x0f,
	0x22, 0x10, 0x87, 0xeb, 0x86, 0xd4, 0x9c, 0x95, 0x4c, 0x15,
	0x8a, 0xb0, 0xd7, 0xbc, 0x2e, 0xca, 0xca, 0x37, 0x28, 0x01,
	// varint encoding of IpcConnectionContext length 
	0x12, // = 18
	0x12, 0x0a, 0x0a, 0x08, 0x65, 0x6c, 0x65, 0x69, 0x62, 0x6f,
	0x76, 0x69, 0x1a, 0x04, 0x70, 0x69, 0x6e, 0x67,

This is the standard header sent before any RPC call is made. Now starts a stream of RPC messages

	// Size of size delimited
	// RpcRequestHeader + RpcRequest protobuf objects
	0x00, 0x00, 0x00, 0x3f, // = 63
	// varint size of RpcRequest Header
	0x1a, // = 26
	0x08, 0x01, 0x10, 0x00, 0x18, 0x00, 0x22, 0x10, 0x87, 0xeb,
	0x86, 0xd4, 0x9c, 0x95, 0x4c, 0x15, 0x8a, 0xb0, 0xd7, 0xbc,
	0x2e, 0xca, 0xca, 0x37, 0x28, 0x00,
	// RPC Request writable. It's not size delimited
	// long - RPC version
	0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x02, // = 2
	// utf8 string - protocol name
	0x00, 0x04, // string legnth = 4
	// p     i     n     g
	0x70, 0x69, 0x6e, 0x67,
	// utf8 string - method name
	0x00, 0x04, // string legnth = 4
	// p     i     n     g
	0x70, 0x69, 0x6e, 0x67,
	// long - client version
	0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, // = 1
	// int - client method hash
	0xa0, 0xbd, 0x17, 0xcc,
	// int - parameter class length
	0x00, 0x00, 0x00, 0x00,

Since the nc -l 5121 server does not respond, the client will eventually send a ping message.

	// ping request
	0xff, 0xff, 0xff, 0xff,

How would we get the server message? Let's use the client request file we've recorded earlier, and feed it to nc as a Hadoop RPC client demiculu. Note we need to wait for input, hence sleep before closing nc's input stream.

	$ (cat client.dat;sleep 5) | nc localhost 5121 |hexdump -C
	00000000  00 00 00 33 1a 08 00 10  00 18 09 3a 10 9b 19 9b  |...3.......:....|
	00000010  41 4d 86 42 d7 94 79 3f  4b 16 a0 22 7c 40 00 00  |AM.B..y?K.."|@..|
	00000020  10 6a 61 76 61 2e 6c 61  6e 67 2e 53 74 72 69 6e  |.java.lang.Strin|
	00000030  67 00 04 70 6f 6e 67                              |g..pong|
	00000037

adding some annotation will make that more clear:
	
	// size of entire request
	0x00, 0x00, 0x00, 0x33,
	// varint size of RpcResponseHeader
	0x1a, // 16 + 10 = 26
	0x08, 0x00, 0x10, 0x00, 0x18, 0x09, 0x3a, 0x10, 0x9b, 0x19,
	0x9b, 0x41, 0x4d, 0x86, 0x42, 0xd7, 0x94, 0x79, 0x3f, 0x4b,
	0x16, 0xa0, 0x22, 0x7c, 0x40, 0x00,
	// Writable response
	// short - length of declared class
	0x00, 0x10,
	// j     a     v     a     .     l     a     n     g     .
	0x6a, 0x61, 0x76, 0x61, 0x2e, 0x6c, 0x61, 0x6e, 0x67, 0x2e,
	// S     t     r     i     n     g 
	0x53, 0x74, 0x72, 0x69, 0x6e, 0x67,
	// short - length of value
	0x00, 0x04,
	// p     o     n     g
	0x70, 0x6f, 0x6e, 0x67,

This are the essential details of a Hadoop RPC server. You can see example go code that parses Hadoop RPC on the [main_test.go](https://github.com/elazarl/hadoop_rpc_walktrhough/blob/master/go_hadoop_rpc/main_test.go#L115) test that walks through an example static binary output, or a very simple ping [rpc client](https://github.com/elazarl/hadoop_rpc_walktrhough/blob/master/go_hadoop_rpc/main.go).


Transform From ： [官方wiki](https://wiki.apache.org/hadoop/HadoopRpc)