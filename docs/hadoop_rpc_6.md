# Hadoop Yarn源码阅读 -- hadoop RPC的发展及其应用层协议格式 #

## RPC发展 ##

<table>
<tbody>
<tr>
<th>svn版本号</th>
<th>patch   号</th>
<th>Server Version</th>
<th>时间</th>
<th>描述</th>
</tr>
<tr>
<td>r374733</td>
<td></td>
<td>#NA</td>
<td>2006-02-04</td>
<td>改包名从Nutch到org.apache.hadoop.ipc</td>
</tr>
<tr>
<td>r411254</td>
<td>HADOOP-211</td>
<td>#NA</td>
<td>2006-06-03</td>
<td>Switch logging use the Jakarta Commons logging API, configured to use log4j by default.用log4j</td>
</tr>
<tr>
<td>r413958</td>
<td>HADOOP-210</td>
<td>#NA</td>
<td>2006-06-14</td>
<td>Change RPC server to use a selector instead of a thread per connection. This should make it easier to scale to larger clusters. Contributed by Devaraj Das.</td>
</tr>
<tr>
<td>r421841</td>
<td>HADOOP-252</td>
<td>#NA</td>
<td>2006-07-14</td>
<td>Add versioning to RPC protocols. Contributed by Milind.就是添加了一个接口校验的版本号</td>
</tr>
<tr>
<td>r477433</td>
<td>HADOOP-677</td>
<td> #NA</td>
<td>2006-11-21</td>
<td>In IPC, permit a version header to be transmitted when connections are established. Contributed by Owen.差不多有传输层验证的雏形</td>
</tr>
<tr>
<td>r601221</td>
<td>HADOOP-2184</td>
<td>1</td>
<td>2007-12-05</td>
<td>RPC Support for user permissions and authentication.</p>
<p>(Raghu Angadi via dhruba)开始考虑安全的事情了</td>
</tr>
<tr>
<td>r603795</td>
<td>HADOOP-1841</td>
<td>1</td>
<td>2007-12-13</td>
<td>Prevent slow clients from consuming threads in the NameNode.</p>
<p>(dhruba),添加了Response线程</td>
</tr>
<tr>
<td>r611906</td>
<td>HADOOP-2398</td>
<td>1</td>
<td>2008-01-15</td>
<td>Additional instrumentation for NameNode and RPC server.</p>
<p>Add support for accessing instrumentation statistics via JMX.</p>
<p>(Sanjay radia via dhruba)</td>
</tr>
<tr>
<td>r614597</td>
<td></td>
<td>1</td>
<td>2008-01-24</td>
<td>成为apache的顶级项目。跟RPC没有多大关系，记录下里程碑事件。</td>
</tr>
<tr>
<td>r639057</td>
<td>HADOOP-2910</td>
<td>1</td>
<td>2008-03-20</td>
<td>Throttle IPC Client/Server during bursts of</p>
<p>requests or server slowdown. (Hairong Kuang via dhruba)，其实就是用了LinkedBlockingQueue阻塞式队列。只是没有想到引进这个是为了长度限制，而不是为了性能。</td>
</tr>
<tr>
<td>r653607</td>
<td>HADOOP-2188.</td>
<td>2</td>
<td>2008-05-05</td>
<td>RPC should send a ping rather than use client timeouts. Contributed by Hairong Kuang.</td>
</tr>
<tr>
<td>r725603</td>
<td>HADOOP-4348</td>
<td>3</td>
<td>2008-12-11</td>
<td>Add service-level authorization for Hadoop.在安全上迈出一大步</td>
</tr>
<tr>
<td>r816727</td>
<td>HADOOP-6170</td>
<td>3</td>
<td>2009-09-19</td>
<td>Add facility to tunnel Avro RPCs through Hadoop RPCs.在数据封装上开始考虑用Avro了</td>
</tr>
<tr>
<td>r889889</td>
<td>HADOOP-6422</td>
<td>3</td>
<td>2009-12-12</td>
<td>Make RPC backend plugable.一次较大的重构，其实是为了提供接口，使上层更好地扩展</td>
</tr>
<tr>
<td>r905860</td>
<td>HADOOP-6419</td>
<td>4</td>
<td>2010-02-03</td>
<td>Change RPC layer to support SASL based mutual authentication 0.21.0 看来不断地增强安全功能</td>
</tr>
<tr>
<td>r917737</td>
<td>HADOOP-6599</td>
<td>4</td>
<td>2010-03-01</td>
<td>Split existing RpcMetrics into RpcMetrics &amp; RpcDetailedMetrics.</td>
</tr>
<tr>
<td>r938590</td>
<td>HADOOP-6713</td>
<td>4</td>
<td>2010-04-27</td>
<td>The RPC server Listener thread is a scalability bottleneck. Contributed by Dmytro Molkov.添加一个Reader线程</td>
</tr>
<tr>
<td>r1064919</td>
<td>HADOOP-6904</td>
<td>4</td>
<td>2011-01-28</td>
<td>A baby step towards inter-version RPC communications，在VersionedProtocol添加getProtocolSignature接口.思考版本之间的兼容性问题</td>
</tr>
<tr>
<td>r1083957</td>
<td>HADOOP-6949</td>
<td>5</td>
<td>2011-03-21</td>
<td>io Reduces RPC packet size for primitive arrays, especially long[], which is used at block reporting</td>
</tr>
<tr>
<td>r1099284</td>
<td>HADOOP-7227</td>
<td>5</td>
<td>2011-05-03</td>
<td>Remove protocol version check at proxy creation in Hadoop RPC. Contributed by jitendra 把验证迁移到服务器端</td>
</tr>
<tr>
<td>r1329696</td>
<td>MAPREDUCE-4079</td>
<td>5</td>
<td>2012-04-24</td>
<td>Allow MR AppMaster to limit ephemeral port range.(bobby via tgraves),就是提供一组ip，Server是不能绑定的。</td>
</tr>
</tbody>
</table>

## 二、hadoop RPC 0.23.4 的数据格式 ##

![](https://github.com/loull521/hadoop-yarn-src-read/raw/master/raw/pictures/rpc_version_1.jpg)

从图中我们看出请求报文主要分为三个部分。第一步包括6个字节，”hrpc”+一个版本号+安全认证方式。第二部分是ConnectionHeader信息，包括protocol和一些安全信息。第三部分是Writable这个就需要看RpcEngine的子类的实现方式，如：WritableRpcEngine是用Invocation，包括一些基本的调用信息。第二部分和第三部分不是固定长度，所以加了长度，占位4个字节。

返回报文比较简单，就直接call.id+status.state+xxx，xxx的信息需要根据status.state来确定，如果是0，则是 结果。如果是1，-1则是errorClass及error。


----------

来自：

[hadoop RPC的发展及其应用层协议格式](http://fengshenwu.com/blog/2012/11/13/hadoop-rpc_develop/)