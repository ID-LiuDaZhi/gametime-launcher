import vm from 'node:vm';
import {webcrypto} from 'node:crypto';
import assert from 'node:assert/strict';

export async function testMobilePage(html) {
 const code=html.match(/<script>([\s\S]*?)<\/script>/)[1];
 const commands=[];let reveal=false;
 function element(){return {textContent:'',className:'',disabled:false,style:{},dataset:{},children:[],replaceChildren(){this.children=[]},appendChild(child){this.children.push(child)}}}
 function phone(){
  const storage=new Map(),ids=new Map(),buttons=['previous','next','play','back','fullscreen'].map(action=>Object.assign(element(),{dataset:{action}}));let poll;
  const document={hidden:false,getElementById(id){if(!ids.has(id))ids.set(id,element());return ids.get(id)},querySelectorAll(selector){return selector==='[data-action]'?buttons:[...buttons,...(ids.get('games')?.children||[])]},createElement:element,addEventListener(){}};
  const context=vm.createContext({document,crypto:webcrypto,Uint8Array,URLSearchParams,AbortController,Date,location:{hash:'#code=shared-key',pathname:'/'},history:{replaceState(){}},sessionStorage:{getItem:key=>storage.get(key)||null,setItem:(key,value)=>storage.set(key,value)},setTimeout,clearTimeout,setInterval:fn=>{poll=fn},fetch:async(path,options)=>{
   const clientId=options.headers['X-GameTime-Client'];assert.match(clientId,/^[0-9a-f]{32}$/);assert.equal(options.headers['X-GameTime-Key'],'shared-key');
   if(path==='/api/action'){const requestId='request-'+commands.length;commands.push({id:requestId,clientId,ok:true,message:'已执行 '+requestId});return {ok:true,json:async()=>({requestId})}}
   return {ok:true,json:async()=>({games:[{id:'one',name:'双人成行'},{id:'two',name:'链在一起'}],selectedId:'two',selectedName:'链在一起',connectedClients:2,receipts:reveal?commands.filter(x=>x.clientId===clientId):[],lastCommand:commands.at(-1)})};
  }});
  new vm.Script(code).runInContext(context);
  return {storage,ids,buttons,poll:()=>poll()};
 }
 const a=phone(),b=phone();await new Promise(setImmediate);
 assert.notEqual(a.storage.get('gametime-client'),b.storage.get('gametime-client'));
 await a.buttons.find(x=>x.dataset.action==='next').onclick();
 await b.buttons.find(x=>x.dataset.action==='next').onclick();
 assert.equal(commands.length,2);assert.equal(a.buttons[0].disabled,true);assert.equal(b.buttons[0].disabled,true);
 reveal=true;await a.poll();await b.poll();
 assert.equal(a.ids.get('message').textContent,'已执行 request-0');assert.equal(b.ids.get('message').textContent,'已执行 request-1');
 assert.equal(a.buttons[0].disabled,false);assert.equal(b.buttons[0].disabled,false);
 assert.equal(a.ids.get('selected').textContent,b.ids.get('selected').textContent);
 assert.match(a.ids.get('status').textContent,/2 个遥控端/);
 return 'PASS: 两个独立手机页面编号、交错指令、各自回执解锁、共享当前选择、在线遥控端数量';
}
