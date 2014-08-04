# Hadoop Yarn源码阅读 -- hadoop RPC框架总体介绍(一) #

## 一、简单的RPC框架 ##

![图1 简单RPC框架](https://raw.githubusercontent.com/loull521/hadoop-yarn-src-read/master/raw/pictures/simple-rpc.png)

Server有XxxProtocol协议的实现，启动后等待Client的RPC请求。

Client用`XxxProtocol`生成代理对象proxy，然后调用`proxy#request()`方法，这会触发`InvokeHandler#invoke()`方法(基于反射)，invoke()方法会跟Server远程通信，从Server获取调用结果，返回给Client，这就完成了一次RPC调用。

Client端采用了动态代理模式。如果不采用动态代理模式，客户端需要实现XxxProtocol协议接口，在每个实现的方法里面，需要远程调用服务器端的XxxProtocol的实现。使用了动态代理，可以免去用户自己去实现客户端和服务器之前协议方法的一一映射关系。

## 二、早期的Hadoop RPC框架 ##

上面是简化的RPC模型，早期的Hadoop RPC框架，如下，

![图2 早期hadoop RPC框架](https://raw.githubusercontent.com/loull521/hadoop-yarn-src-read/master/raw/pictures/hadoop-rpc-old.jpg)

说明：

- `RPC`：是一个工厂，能生产特定协议的客户端代理proxy和服务器端Server实例。
- `MyProtocol`：是用户要通信的协议，它必须实现VersionedProtocol。
- `RPC.Invocation`：它继承了Writable，表明是一个可序列化对象。它封装了函数调用信息(函数名、函数参数列表)，由于要在网络上传输，必须可序列化。
- `Client`：它负责跟服务器网络通信，`RPC.Invoker#invoke()`会调用`Client#call()`方法。

MyClient是客户端程序，通过RPC.getProxy()获取代理对象proxy，然后用proxy的方法发起RPC远程调用。经过反射触发RPC.Invoker#invoke()方法，它交给Client#call()去处理。call把函数调用信息序列化发给Server，server处理过返回给Client。

## 三、hadoop 2.4.1 的RPC框架变化 ##

最近版本的hadoop RPC框架变化不大，主要把序列化过程独立出来，可以用第三方序列化工具，比如Protocol buffer。

序列化模块交给RpcEngine的子类去完成。而不论是Client还是Server，通信模块都依赖于序列化，所以最终getProxy()和getServer()都在RpcEngine的子类完成。

RPC工厂的变化：

![](https://raw.githubusercontent.com/loull521/hadoop-yarn-src-read/master/raw/pictures/RPC-new.jpg)

----------

Client端的变化，这里变化不大，就是把Client的实例化过程推迟，放到RpcInvokerHandler的子类里面。
![](https://raw.githubusercontent.com/loull521/hadoop-yarn-src-read/master/raw/pictures/client-new.jpg)

----------

Server端的变化：很明显的，把处理客户端请求的过程交给RpcInvoke的子类去完成。
![](https://raw.githubusercontent.com/loull521/hadoop-yarn-src-read/master/raw/pictures/server-new.jpg)
