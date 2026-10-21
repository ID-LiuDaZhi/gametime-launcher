using System;
using System.Collections;
using System.Collections.Generic;
using System.Linq;

namespace GameTime {
 public sealed class RemoteClients {
  readonly Dictionary<string,DateTime> seen=new Dictionary<string,DateTime>();
  readonly object gate=new object();
  public static bool Valid(string client){return client!=null&&client.Length==32&&client.All(c=>Uri.IsHexDigit(c));}
  void Prune(DateTime now){foreach(string id in seen.Where(x=>(now-x.Value).TotalSeconds>15).Select(x=>x.Key).ToArray())seen.Remove(id);}
  public bool Touch(string client,DateTime now){if(!Valid(client))return false;lock(gate){Prune(now);if(!seen.ContainsKey(client)&&seen.Count>=64)return false;seen[client]=now;return true;}}
  public int Count(DateTime now){lock(gate){Prune(now);return seen.Count;}}
 }
 public sealed class RemoteReceipt {
  public string id {get;set;}
  public string clientId {get;set;}
  public bool ok {get;set;}
  public string message {get;set;}
  public DateTime created {get;set;}
 }
 public sealed class RemoteReceipts {
  readonly List<RemoteReceipt> items=new List<RemoteReceipt>();
  void Prune(DateTime now){items.RemoveAll(x=>(now-x.created).TotalMinutes>2);if(items.Count>512)items.RemoveRange(0,items.Count-512);}
  public void Record(string id,string client,bool ok,string message,DateTime now){if(!RemoteClients.Valid(client))throw new ArgumentException("Invalid client");items.Add(new RemoteReceipt{id=id,clientId=client,ok=ok,message=message,created=now});Prune(now);}
  public RemoteReceipt[] ForClient(string client,DateTime now){Prune(now);return items.Where(x=>x.clientId==client).ToArray();}
  public RemoteReceipt[] Snapshot(DateTime now){Prune(now);return items.ToArray();}
 }
 public sealed class RemoteCommandOrder {
  long last;
  readonly object gate=new object();
  public long Next(long timestamp){lock(gate){last=Math.Max(timestamp,last+1);return last;}}
 }
 public static class RemoteStateView {
  // A shared computer state is visible to all phones; execution receipts belong to their sender.
  public static void FilterReceipts(Dictionary<string,object> state,string client,int online){
   object all;var own=new List<Dictionary<string,object>>();
   if(state.TryGetValue("receipts",out all)&&all is IEnumerable){foreach(object item in (IEnumerable)all){var receipt=item as Dictionary<string,object>;object owner;if(receipt!=null&&receipt.TryGetValue("clientId",out owner)&&String.Equals(owner as string,client,StringComparison.Ordinal))own.Add(receipt);}}
   state["receipts"]=own.ToArray();state["lastCommand"]=own.Count==0?(object)new Dictionary<string,object>():own[own.Count-1];state["connectedClients"]=online;
  }
 }
}
