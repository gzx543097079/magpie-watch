/* Local-only scene. Particles illustrate trace events, never imply per-token streaming telemetry. */
(() => {
'use strict';
const T = window.THREE;
const query = new URLSearchParams(location.search);
const motion = matchMedia('(prefers-reduced-motion: reduce)');
const $ = id => document.getElementById(id);
const C = { in:0x68ebff, out:0xffbc7d, error:0xff6e88, white:0xe9fdff };
let renderer;
try { renderer = new T.WebGLRenderer({canvas:$('scene'),antialias:true,alpha:false,powerPreference:'low-power'}); }
catch (_) { $('failure').hidden=false; return; }
renderer.setPixelRatio(Math.min(devicePixelRatio || 1, 1.5));
renderer.setClearColor(0x020812);
renderer.outputEncoding=T.sRGBEncoding;
const scene=new T.Scene();
const camera=new T.PerspectiveCamera(42,innerWidth/innerHeight,.1,120);
camera.position.set(0,1,27); camera.lookAt(0,0,0);
const v3=(x=0,y=0,z=0)=>new T.Vector3(x,y,z);
const additive=(color,opacity=1)=>new T.MeshBasicMaterial({color,transparent:true,opacity,blending:T.AdditiveBlending,depthWrite:false,side:T.DoubleSide});
function glowTexture(){const c=document.createElement('canvas');c.width=c.height=128;const x=c.getContext('2d'),g=x.createRadialGradient(64,64,0,64,64,64);g.addColorStop(0,'rgba(255,255,255,1)');g.addColorStop(.09,'rgba(255,255,255,.7)');g.addColorStop(.3,'rgba(255,255,255,.15)');g.addColorStop(1,'rgba(255,255,255,0)');x.fillStyle=g;x.fillRect(0,0,128,128);return new T.CanvasTexture(c);}
const glowMap=glowTexture();
function glow(parent,color,size,opacity){const o=new T.Sprite(new T.SpriteMaterial({map:glowMap,color,transparent:true,opacity,blending:T.AdditiveBlending,depthWrite:false}));o.scale.setScalar(size);parent.add(o);return o;}
let time=0,lastFrame=0,energy=0;
const uniforms={time:{value:0},energy:{value:0}};
// Very slow nebula is an environmental layer, independent of traffic.
const backdrop=new T.Mesh(new T.PlaneGeometry(92,54),new T.ShaderMaterial({depthWrite:false,uniforms,vertexShader:'varying vec2 uv0; void main(){uv0=uv;gl_Position=projectionMatrix*modelViewMatrix*vec4(position,1.);}',fragmentShader:`varying vec2 uv0; uniform float time; uniform float energy;
float hash(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
float noise(vec2 p){vec2 i=floor(p),f=fract(p);f=f*f*(3.-2.*f);return mix(mix(hash(i),hash(i+vec2(1.,0.)),f.x),mix(hash(i+vec2(0.,1.)),hash(i+1.),f.x),f.y);}
void main(){vec2 p=(uv0-.5)*vec2(1.7,1.);float n=noise(p*5.+vec2(time*.012,0.));n+=.5*noise(p*11.+n);float ribbon=exp(-abs(p.y+.13*sin(p.x*5.+n+time*.025))*(12.+n*9.));float mask=exp(-length(p*vec2(.8,1.1))*2.);vec3 col=vec3(.004,.012,.027)+ribbon*mask*vec3(.025,.14,.22)*(n+.2);col+=exp(-length(p-vec2(.42,-.12))*6.)*vec3(.12,.042,.018);col+=pow(max(0.,n-.5),3.)*mask*vec3(.018,.028,.06);gl_FragColor=vec4(col,1.);}`}));
backdrop.position.z=-20;scene.add(backdrop);
// Far stars; fixed seeded positions keep every launch composed consistently.
let seed=12983;function random(){seed=(seed*1664525+1013904223)>>>0;return seed/4294967296;}
const starGeo=new T.BufferGeometry(),starPos=new Float32Array(1500*3),starColors=new Float32Array(1500*3);
for(let i=0;i<1500;i++){starPos.set([(random()-.5)*90,(random()-.5)*45,-8-random()*28],i*3);let c=new T.Color().setHSL(.54+random()*.1,.35,.35+random()*.5);starColors.set([c.r,c.g,c.b],i*3);}
starGeo.setAttribute('position',new T.BufferAttribute(starPos,3));starGeo.setAttribute('color',new T.BufferAttribute(starColors,3));const stars=new T.Points(starGeo,new T.PointsMaterial({size:.055,vertexColors:true,transparent:true,opacity:.67,depthWrite:false}));scene.add(stars);
// The gateway is a dimensional accretion field with a dark, pearl-edged core.
const hub=new T.Group();hub.position.y=.1;scene.add(hub);
const core=new T.Mesh(new T.SphereGeometry(1.98,64,48),new T.ShaderMaterial({uniforms,vertexShader:`varying vec3 n;varying vec3 eye;varying vec3 pos;void main(){n=normalize(normalMatrix*normal);vec4 p=modelViewMatrix*vec4(position,1.);eye=normalize(-p.xyz);pos=position;gl_Position=projectionMatrix*p;}`,fragmentShader:`varying vec3 n;varying vec3 eye;varying vec3 pos;uniform float time;uniform float energy;void main(){float rim=pow(1.-max(0.,dot(n,eye)),3.5);float band=.5+.5*sin(pos.y*16.+sin(pos.x*9.+time*.5)*2.);vec3 c=vec3(.002,.009,.021)+rim*vec3(.13,.72,.89)*(1.+energy*.5);c+=rim*band*vec3(.04,.18,.2);gl_FragColor=vec4(c,1.);}`}));hub.add(core);
const halo=glow(hub,0x178fd9,14,.38);
const disk=new T.Group();disk.rotation.set(1.03,.1,-.34);hub.add(disk);
// A continuous, turbulent disk provides volume between the orbital filaments.
const accretion=new T.Mesh(new T.RingGeometry(2.12,5.8,256,12),new T.ShaderMaterial({
  uniforms,transparent:true,depthWrite:false,side:T.DoubleSide,blending:T.AdditiveBlending,
  vertexShader:`varying vec3 local;void main(){local=position;vec3 p=position;p.z+=sin(length(p.xy)*5.)*.035;gl_Position=projectionMatrix*modelViewMatrix*vec4(p,1.);}`,
  fragmentShader:`varying vec3 local;uniform float time;uniform float energy;
  float hash(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
  float noise(vec2 p){vec2 i=floor(p),f=fract(p);f=f*f*(3.-2.*f);return mix(mix(hash(i),hash(i+vec2(1.,0.)),f.x),mix(hash(i+vec2(0.,1.)),hash(i+1.),f.x),f.y);}
  void main(){float r=length(local.xy),a=atan(local.y,local.x);float t=time*.14;
    vec2 flow=vec2(cos(a-t/(r*.3)),sin(a-t/(r*.3)))*r;
    float n=noise(flow*3.);n+=.5*noise(flow*8.+n);n+=.2*noise(flow*19.);
    float filaments=pow(.5+.5*sin(r*85.+n*6.+a*3.-t*4.),4.);
    float spirals=pow(.5+.5*sin(a*5.-r*6.+n*2.-t),3.);
    float inner=exp(-(r-2.12)*2.4),edge=exp(-abs(r-2.22)*18.);
    float fade=(1.-smoothstep(3.1,5.8,r))*smoothstep(2.12,2.22,r);
    float brightness=(.07+filaments*.7+spirals*.24)*fade*(.35+n*.6);
    vec3 cold=mix(vec3(.025,.15,.5),vec3(.12,.75,1.),inner);
    float warm=pow(.5+.5*sin(a-1.2),5.)*.72;
    vec3 color=mix(cold,vec3(1.,.36,.10),warm);
    color=color*brightness+vec3(.35,.8,1.)*edge*.6;
    gl_FragColor=vec4(color*(1.+energy*.25),fade*.8+edge*.35);
  }`
}));disk.add(accretion);
const dustCount=9200,dustGeo=new T.BufferGeometry(),dustPos=new Float32Array(dustCount*3),dustColor=new Float32Array(dustCount*3);
for(let i=0;i<dustCount;i++){const a=random()*Math.PI*2,r=2.17+Math.pow(random(),2)*3.4;dustPos.set([Math.cos(a)*r,Math.sin(a)*r,(random()-.5)*.11*(r-1.5)],i*3);const mix=Math.max(0,(r-2.25)/2.6),color=new T.Color(C.in).lerp(new T.Color(0x215c93),mix);if(i%13===0)color.setHex(C.out);color.multiplyScalar(.45+random()*.8);dustColor.set([color.r,color.g,color.b],i*3);}
dustGeo.setAttribute('position',new T.BufferAttribute(dustPos,3));dustGeo.setAttribute('color',new T.BufferAttribute(dustColor,3));const dust=new T.Points(dustGeo,new T.PointsMaterial({size:.095,map:glowMap,vertexColors:true,blending:T.AdditiveBlending,transparent:true,opacity:.95,depthWrite:false}));disk.add(dust);
const rings=[];
for(let i=0;i<3;i++){const r=2.17+i*.93,g=new T.TorusGeometry(r,i===0?.022:.009,8,200,Math.PI*(i%2?1.65:1.9)),m=new T.Mesh(g,additive(i%3===0?0x3cbaf5:C.in,i===0?.52:.17));m.rotation.z=i*1.7;disk.add(m);rings.push(m);}
const outer=new T.Mesh(new T.TorusGeometry(4.3,.012,6,240,5.5),additive(C.in,.2));outer.rotation.set(.35,.6,-.8);hub.add(outer);
const floor=new T.Mesh(new T.RingGeometry(4.8,4.82,180),additive(C.in,.12));floor.rotation.x=-Math.PI/2;floor.position.y=-4.3;scene.add(floor);
hub.scale.setScalar(.84);
// ---- Active-only constellation: a node exists only while a real route references it. ----
const nodes=new Map(),paths=new Map(),flights=new Map(),seen=new Set(),bursts=[];
let data={agents:[],models:[],flows:[],online:false,inputTokens:0,outputTokens:0,calls:0,preview:false,dashboard:null};
let livePayload=null,preview=false,demoClock=0,demoSeq=0,nodeX=6.1;
function compact(n){n=Math.max(0,Number(n)||0);return n>=1e9?(n/1e9).toFixed(2)+'B':n>=1e6?(n/1e6).toFixed(2)+'M':n>=1e3?(n/1e3).toFixed(1)+'k':String(Math.round(n));}
function money(n){return n==null?'—':'$'+Number(n).toFixed(2);}
function seconds(ms){return ms==null?'—':ms>=1000?(ms/1000).toFixed(2)+' s':Math.round(ms)+' ms';}
function dispose(object){object.traverse(o=>{if(o.geometry)o.geometry.dispose();if(o.material)o.material.dispose();});if(object.parent)object.parent.remove(object);}
function nodeKey(side,id){return side+':'+id;}
function el(tag,className,text){const e=document.createElement(tag);if(className)e.className=className;if(text!=null)e.textContent=text;return e;}
function easeOutBack(x){const c=1.9;return 1+(c+1)*Math.pow(x-1,3)+c*Math.pow(x-1,2);}
function slot(side,index,total){
  const spacing=total>1?Math.min(1.85,8.2/(total-1)):0;
  return v3(side*(nodeX+Math.sin(index*1.7+side)*.35),hub.position.y+(total-1)/2*spacing-index*spacing,(index%3-1)*.55);
}
function makeNode(side,key){
  const group=new T.Group();scene.add(group);
  const color=side<0?C.in:C.out;
  const core=new T.Mesh(side<0?new T.IcosahedronGeometry(.17,1):new T.OctahedronGeometry(.21,0),new T.MeshBasicMaterial({color:side<0?0x7ef3ff:0xffc995}));
  const shell=new T.Mesh(side<0?new T.IcosahedronGeometry(.36,0):new T.DodecahedronGeometry(.4,0),new T.MeshBasicMaterial({color,wireframe:true,transparent:true,opacity:.5,blending:T.AdditiveBlending,depthWrite:false}));
  const rings=[0,1].map(i=>{const r=new T.Mesh(new T.TorusGeometry(.56+i*.17,i?.006:.011,6,80,Math.PI*(i?1.4:2)),additive(color,i?.35:.5));r.rotation.x=.5+i*.7;group.add(r);return r;});
  const light=glow(group,color,2.6,.3);
  const beam=new T.Sprite(new T.SpriteMaterial({map:glowMap,color,transparent:true,opacity:.0,blending:T.AdditiveBlending,depthWrite:false}));beam.scale.set(.32,7,1);group.add(beam);
  group.add(core,shell);
  const label=el('div','node-label '+(side<0?'agent':'model'));const title=el('b'),detail=el('small'),live=el('span','live');label.append(title,detail,live);label.style.opacity='0';$('labels').append(label);
  const n={key,side,group,core,shell,rings,light,beam,label,title,detail,live,index:0,target:v3(),appear:motion.matches?1:0,leaving:false,flash:0,busy:0,liveText:''};
  nodes.set(key,n);makePath(n);return n;
}
function reconcile(list,side){
  const wanted=list.slice(0,8).map(d=>({d,key:nodeKey(side,d.id)}));
  const keys=new Set(wanted.map(w=>w.key));
  // A node whose request is still returning stays until that light reaches the agent.
  for(const p of flights.values()){const k=side<0?p.a:p.m;if(!keys.has(k)&&nodes.has(k)){keys.add(k);wanted.push({d:null,key:k});}}
  wanted.forEach(({d,key},i)=>{
    let n=nodes.get(key);const fresh=!n;if(!n)n=makeNode(side,key);
    n.index=i;n.target.copy(slot(side,i,wanted.length));n.leaving=false;
    if(fresh){n.group.position.copy(n.target);if(!motion.matches)pulse(n.target,side<0?C.in:C.out,1.6);}
    if(d){n.name=d.name;n.title.textContent=d.name;n.detail.textContent=side<0?'今日 '+compact(d.calls)+' 次调用':(d.sub||'模型')+(d.calls?' · 今日 '+compact(d.calls)+' 次':'');}
  });
  for(const [key,n] of nodes)if(n.side===side&&!keys.has(key))n.leaving=true;
  $(side<0?'agent-rail':'model-rail').className='rail '+(side<0?'agent-rail':'model-rail')+([...nodes.values()].some(n=>n.side===side&&!n.leaving)?'':' off');
}
function removeNode(n){n.label.remove();dispose(n.group);const p=paths.get(n.key);if(p){dispose(p.input.mesh);dispose(p.output.mesh);paths.delete(n.key);}nodes.delete(n.key);}

// ---- Token streams: shader ribbons whose dashes travel in the direction tokens move. ----
const STREAM_SEGMENTS=80;
const streamVertex='varying vec2 v;void main(){v=uv;gl_Position=projectionMatrix*modelViewMatrix*vec4(position,1.);}';
const streamFragment=`varying vec2 v;uniform vec3 color;uniform float time;uniform float uDir;uniform float uActive;uniform float uVisible;
void main(){
  float x=v.x-.5;float cross=exp(-x*x*18.);float spine=exp(-x*x*220.);
  float flow=v.y*7.-time*1.15*uDir;
  float dashes=pow(.5+.5*sin((v.y*46.-time*6.5*uDir)*1.),10.);
  float surge=pow(fract(flow),7.)+pow(fract(flow*.37+.3),12.)*.8;
  float ends=smoothstep(0.,.05,v.y)*smoothstep(1.,.93,v.y);
  float a=(spine*.32+cross*.06)+uActive*(cross*dashes*.75+cross*surge*.95+spine*.35);
  gl_FragColor=vec4(color*(1.+spine*.8+uActive*surge*.6),a*ends*uVisible);
}`;
function makeStream(color,dir){
  const geometry=new T.BufferGeometry(),positions=new Float32Array(STREAM_SEGMENTS*6),uv=new Float32Array(STREAM_SEGMENTS*4),index=[];
  for(let i=0;i<STREAM_SEGMENTS;i++){const t=i/(STREAM_SEGMENTS-1);uv.set([0,t,1,t],i*4);if(i<STREAM_SEGMENTS-1){const a=i*2;index.push(a,a+1,a+2,a+1,a+3,a+2);}}
  geometry.setAttribute('position',new T.BufferAttribute(positions,3));geometry.setAttribute('uv',new T.BufferAttribute(uv,2));geometry.setIndex(index);
  const material=new T.ShaderMaterial({transparent:true,depthWrite:false,side:T.DoubleSide,blending:T.AdditiveBlending,uniforms:{color:{value:new T.Color(color)},time:uniforms.time,uDir:{value:dir},uActive:{value:0},uVisible:{value:0}},vertexShader:streamVertex,fragmentShader:streamFragment});
  const mesh=new T.Mesh(geometry,material);mesh.frustumCulled=false;scene.add(mesh);
  return {mesh,positions,curve:new T.CubicBezierCurve3(v3(),v3(),v3(),v3()),heat:0};
}
function makePath(n){paths.set(n.key,{input:makeStream(C.in,1),output:makeStream(C.out,-1)});}
function setCurve(curve,start,end,lane){const dir=Math.sign(end.x-start.x)||1;curve.v0.copy(start).y+=lane;curve.v1.set(start.x+dir*2.6,start.y+lane*2.4,start.z+1.4);curve.v2.set(end.x-dir*2.6,end.y+lane*2.4,end.z+1.4);curve.v3.copy(end).y+=lane;}
const tmpA=v3(),tmpB=v3();
function layStream(stream,width){
  for(let i=0;i<STREAM_SEGMENTS;i++){
    const t=i/(STREAM_SEGMENTS-1);stream.curve.getPoint(t,tmpA);stream.curve.getTangent(t,tmpB);
    const nx=-tmpB.y,ny=tmpB.x,len=Math.hypot(nx,ny)||1,w=width*(.55+.45*Math.sin(Math.PI*t));
    stream.positions.set([tmpA.x-nx/len*w,tmpA.y-ny/len*w,tmpA.z,tmpA.x+nx/len*w,tmpA.y+ny/len*w,tmpA.z],i*6);
  }
  stream.mesh.geometry.attributes.position.needsUpdate=true;
}
function updatePaths(dt){
  for(const n of nodes.values()){
    const p=paths.get(n.key);if(!p)continue;
    const a=n.side<0?n.group.position:hub.position,b=n.side<0?hub.position:n.group.position;
    setCurve(p.input.curve,a,b,.2);setCurve(p.output.curve,a,b,-.24);
    for(const s of [p.input,p.output]){
      s.heat=Math.max(0,s.heat-dt*.7);
      s.mesh.material.uniforms.uActive.value=s.heat;s.mesh.material.uniforms.uVisible.value=n.appear;
      layStream(s,.07+s.heat*.07);
    }
  }
}
function pulse(point,color,scale=1){if(motion.matches||bursts.length>=28)return;const mesh=new T.Mesh(new T.RingGeometry(.25,.29,64),additive(color,.75));mesh.position.copy(point);scene.add(mesh);bursts.push({mesh,age:0,scale});energy=Math.min(1.4,energy+.6);}

// ---- Flights: one per real route; head + glowing ribbon + particle wake. ----
const packetGeo=new T.SphereGeometry(.08,10,8);
function makeRibbon(count){
  const geometry=new T.BufferGeometry(),positions=new Float32Array(count*6),uv=new Float32Array(count*4),indices=[];
  for(let i=0;i<count;i++){uv.set([0,i/(count-1),1,i/(count-1)],i*4);if(i<count-1){const a=i*2;indices.push(a,a+1,a+2,a+1,a+3,a+2);}}
  geometry.setAttribute('position',new T.BufferAttribute(positions,3));geometry.setAttribute('uv',new T.BufferAttribute(uv,2));geometry.setIndex(indices);
  const mesh=new T.Mesh(geometry,new T.ShaderMaterial({transparent:true,depthWrite:false,side:T.DoubleSide,blending:T.AdditiveBlending,
    uniforms:{color:{value:new T.Color(C.in)}},
    vertexShader:'varying vec2 v;void main(){v=uv;gl_Position=projectionMatrix*modelViewMatrix*vec4(position,1.);}',
    fragmentShader:'varying vec2 v;uniform vec3 color;void main(){float cross=exp(-pow((v.x-.5)*3.,2.));float tail=pow(1.-v.y,1.5);gl_FragColor=vec4(color*1.35,cross*tail*.85);}'
  }));mesh.frustumCulled=false;scene.add(mesh);return {mesh,positions};
}
function spawn(f){
  if(flights.size>=32)return;const a=nodeKey(-1,f.agentID),m=nodeKey(1,f.destinationID);if(!nodes.has(a)||!nodes.has(m))return;
  const returning=f.stage==='returning';const group=new T.Group();scene.add(group);
  const head=new T.Mesh(packetGeo,additive(C.white,.95));group.add(head);const light=glow(group,C.in,2.1,.7);
  const label=el('div','packet-label');$('packets').append(label);
  const count=Math.min(80,28+Math.ceil(Math.log2(1+Math.max(f.requestTokens||0,f.responseTokens||0))*2.4));
  const positions=new Float32Array(count*3),colors=new Float32Array(count*3);const geometry=new T.BufferGeometry();
  geometry.setAttribute('position',new T.BufferAttribute(positions,3));geometry.setAttribute('color',new T.BufferAttribute(colors,3));
  const trail=new T.Points(geometry,new T.PointsMaterial({size:.3,map:glowMap,vertexColors:true,transparent:true,opacity:.95,blending:T.AdditiveBlending,depthWrite:false}));scene.add(trail);trail.frustumCulled=false;
  const ribbon=makeRibbon(count);
  const p={ribbon,id:f.id,a,m,group,head,light,label,trail,positions,colors,count,age:returning?4.8:f.stage==='outbound'?1.8:0,done:returning,flow:{...f},lastLeg:-1,lastSeen:time};
  flights.set(f.id,p);seen.add(f.id);
  const origin=nodes.get(returning?m:a);origin.flash=1;pulse(origin.group.position,returning?C.out:C.in,1.2);
}
let relayout=false;
function removeFlight(p){relayout=true;scene.remove(p.group);p.head.material.dispose();p.light.material.dispose();dispose(p.trail);dispose(p.ribbon.mesh);p.label.remove();flights.delete(p.id);}
function resetFlights(){for(const p of [...flights.values()])removeFlight(p);seen.clear();}

// ---- Dashboard (plain text only; payload strings are never parsed as HTML). ----
let accountPage=-1;
function renderTelemetry(){
  const show=(id,value)=>{$(id).textContent=value;};
  const measured=data.usageAvailable!==false;
  show('stat-input',measured?compact(data.inputTokens):'—');show('stat-output',measured?compact(data.outputTokens):'—');
  show('stat-cache',data.cacheTokens==null?'—':compact(data.cacheTokens));show('stat-hit',data.cacheHitRate==null?'—':data.cacheHitRate.toFixed(1)+'%');
  show('usage-fresh',preview?'示例统计':!data.usageFresh?'上次数据':compact(data.calls)+' 次请求');
  show('head-calls',measured?compact(data.calls):'—');show('head-hit',data.cacheHitRate==null?'—':data.cacheHitRate.toFixed(1)+'%');
  const accounts=data.accounts||[],pages=Math.max(1,Math.ceil(accounts.length/3));
  const page=motion.matches?0:Math.floor(time/15)%pages;accountPage=page;
  show('account-page',(data.quotasFresh?'':'上次数据 · ')+accounts.length+' 个账号'+(pages>1?' · '+(page+1)+'/'+pages:''));
  const container=$('accounts');container.replaceChildren();
  if(!accounts.length)container.append(el('div','account-user','等待 Magpie 提供账号额度'));
  for(const account of accounts.slice(page*3,page*3+3)){
    const item=el('div',account.remainingPercent!=null&&account.remainingPercent<20?'account-low':'');
    for(const [className,value] of [['account-name',account.name+(account.current?' · 当前':'')],['account-user',account.account],['account-balance',account.balance]])item.append(el('div',className,value));
    if(account.remainingPercent!=null){const track=el('div','account-meter'),bar=el('i');bar.style.width=Math.max(0,Math.min(100,account.remainingPercent))+'%';track.append(bar);item.append(track);}
    container.append(item);
  }
}
function renderDashboard(){
  const d=data.dashboard,today=d&&d.periods?d.periods[0]:null;
  const split=$('token-split');split.replaceChildren();
  if(today&&today.total>0)for(const [cls,value] of [['s-input',today.input],['s-cache',today.cacheRead],['s-write',today.cacheWrite],['s-output',today.output]]){if(!value)continue;const i=el('i',cls);i.style.flex=String(value);split.append(i);}
  const periods=$('periods');periods.replaceChildren();
  ['今日','本周','本月'].forEach((label,i)=>{
    const p=d&&d.periods?d.periods[i]:null,row=el('div','period');
    row.append(el('span',null,label),el('b',null,p?compact(p.total):'待计量'),el('em',null,p&&p.cacheShare!=null?'缓存 '+p.cacheShare.toFixed(1)+'%':''));
    row.append(el('small',null,p?'新输入 '+compact(p.input)+' · 输出 '+compact(p.output)+' · 缓存读 '+compact(p.cacheRead)+' · 写 '+compact(p.cacheWrite)+' · '+money(p.cost):'等待 Magpie 逐日用量'));
    periods.append(row);
  });
  const eff=$('efficiency');eff.replaceChildren();
  const cells=[['请求',d?compact(d.calls):'—',''],['错误',d?String(d.errors):'—',d&&d.errors>0?'warn':''],['重试',d?String(d.retried):'—',''],['会话',d&&d.sessions!=null?String(d.sessions):'—',''],
    ['费用',d?money(d.cost):'—','gold'],['推理',d&&d.reasoning!=null?compact(d.reasoning):'—',''],['平均首字',d?seconds(d.ttftMs):'—',''],['生成速度',d&&d.decodeRate!=null?d.decodeRate.toFixed(0)+' tok/s':'—','']];
  for(const [label,value,cls] of cells){const c=el('div',cls);c.append(el('span',null,label),el('b',null,value));eff.append(c);}
  const hours=$('hours');hours.replaceChildren();
  const series=d&&d.hours?d.hours:[];const max=Math.max(1,...series.map(h=>h.calls));const nowHour=String(new Date().getHours());
  for(const h of series){
    const bar=el('div','hour'+(h.calls?'':' empty')+(h.label===nowHour?' now':''));
    const ok=el('i');ok.style.height=Math.max(2,(h.calls-h.errors)/max*100)+'%';
    if(h.errors>0){const bad=el('u');bad.style.height=Math.max(2,h.errors/max*100)+'%';bar.append(bad);}
    bar.append(ok);hours.append(bar);
  }
  renderRanks('rank-agents',d?d.agents:[],r=>compact(r.tokens)+' tok');
  renderRanks('rank-models',d?d.models:[],r=>r.ttftMs==null?'首字 —':'首字 '+seconds(r.ttftMs));
}
function renderRanks(id,list,middle){
  const box=$(id);box.replaceChildren();
  if(!list||!list.length){box.append(el('div','rank-empty','等待今日调用'));return;}
  const top=Math.max(...list.map(r=>r.calls),1);
  for(const r of list){
    const row=el('div','rank'),name=el('b',null,r.name);name.append(el('small',null,r.sub));
    const nums=el('em',null,compact(r.calls)+' 次');nums.append(el('s',null,middle(r)),el('s','cost',money(r.cost)));
    const bar=el('div','bar'),fill=el('i');fill.style.width=(r.calls/top*100)+'%';bar.append(fill);
    row.append(name,nums,bar);box.append(row);
  }
}
function renderOperations(){
  const container=$('operations');container.replaceChildren();
  $('operations-fresh').textContent=preview?'示例调用':!data.operationsFresh?'上次数据':'新输入 / 缓存 / 输出 · 上下文主项单独展示';
  const operations=(data.operations||[]).slice(0,3);
  if(!operations.length)container.append(el('div','operation-empty','等待真实调用，收到请求后会显示用途与 Token 用量。'));
  for(const op of operations){
    const item=el('div','operation'+(op.active?' active':'')+(op.failed?' failed':''));
    const title=el('div','operation-title');title.append(el('span',null,op.purpose),el('small',null,op.status));item.append(title);
    item.append(el('div','operation-source',op.source));
    const usage=el('div','operation-usage');
    for(const [className,label,value] of [['input','入',op.input],['cache','缓存',op.cache],['output','出',op.output]])usage.append(el('span',className,label+' '+(value==null?'—':compact(value))));
    item.append(usage,el('div','operation-context',op.context||'上下文拆分未提供'));container.append(item);
  }
}
function applyData(next){
  data={...data,...next};renderTelemetry();renderDashboard();renderOperations();
  const flows=data.online?(data.flows||[]):[];
  if(!data.online)resetFlights();
  reconcile(data.online?data.agents||[]:[],-1);reconcile(data.online?data.models||[]:[],1);
  for(const f of flows){
    let p=flights.get(f.id);if(!p&&!seen.has(f.id)){spawn(f);p=flights.get(f.id);}
    if(p){p.lastSeen=time;p.flow={...f};if(f.stage==='returning'&&!p.done){p.done=true;p.age=Math.max(4.8,p.age);const n=nodes.get(p.m);if(n)n.flash=1;pulse(n?n.group.position:hub.position,f.outcome==='ok'?C.out:C.error,1.3);}}
  }
  while(seen.size>600)seen.delete(seen.values().next().value);
  $('led').classList.toggle('online',data.online);$('status').textContent=preview?'演示数据':data.online?'本地网关在线':'本地网关离线';
  $('input').textContent=compact(data.inputTokens);$('output').textContent=compact(data.outputTokens);
  $('inflight').textContent=String(flows.filter(f=>f.stage!=='returning').length);
  $('message').textContent=data.online?'等待下一次请求':'网关离线 · 自动重连中';
  updatePaths(0);
}
window.setMagpieData=function(next){livePayload=next;const wantPreview=!!next.preview||query.has('demo');if(wantPreview!==preview){preview=wantPreview;resetFlights();$('demo').style.display=preview?'block':'none';if(preview){demoClock=0;demoSeq=0;applyData(demoData());demoTick();}else applyData(next);}else if(!preview)applyData(next);};
function demoData(){
  const hours=Array.from({length:24},(_,i)=>({label:String(i),calls:Math.round(40+90*Math.max(0,Math.sin((i-6)/4))+(i%5)*9),errors:i%7===3?4:0,input:0,output:0}));
  return{agents:[{id:'claude',name:'Claude Code',calls:2864},{id:'codex',name:'Codex',calls:1346},{id:'cursor',name:'Cursor',calls:728}],
  models:[{id:'sonnet',name:'Claude · Sonnet',sub:'Anthropic',calls:2864},{id:'gpt',name:'GPT',sub:'OpenAI',calls:1346},{id:'deepseek',name:'DeepSeek',sub:'DeepSeek',calls:728}],
  flows:[],online:true,operationsFresh:true,
  operations:[{purpose:'标题生成',source:'Codex → GPT',status:'已完成',input:160,cache:1200,output:24,context:'上下文主项 · 对话历史 1.2k tok'},{purpose:'模型调用',source:'Claude Code → Claude · Sonnet',status:'进行中 · 待结算',active:true,context:'上下文拆分未提供'},{purpose:'上下文压缩',source:'Cursor → DeepSeek',status:'已完成',input:4300,cache:12000,output:920,context:'上下文主项 · 工具执行返回 8.2k tok'}],
  accounts:[{name:'Codex · PLUS',account:'示例账号 A',balance:'5 小时 剩余 68% · 7 天 剩余 82%',remainingPercent:68},{name:'Claude',account:'示例账号 B',balance:'5 小时 剩余 91%',remainingPercent:91}],
  usageAvailable:true,usageFresh:true,quotasFresh:true,cacheTokens:28924000,cacheHitRate:79.65,inputTokens:7389224,outputTokens:1204368,calls:5091,
  dashboard:{periods:[{label:'今日',total:37800000,input:7389224,output:1204368,cacheRead:28924000,cacheWrite:280000,cacheShare:79.65,calls:5091,cost:41.2},{label:'本周',total:182000000,input:30100000,output:5200000,cacheRead:145000000,cacheWrite:1700000,cacheShare:82.8,calls:21000,cost:190.4},{label:'本月',total:402000000,input:61000000,output:11000000,cacheRead:326000000,cacheWrite:4000000,cacheShare:84.2,calls:47000,cost:401.7}],
    calls:5091,errors:12,retried:9,sessions:14,cost:41.2,reasoning:220000,ttftMs:2380,decodeRate:41,hours,
    agents:[{name:'Claude Code',sub:'智能体',calls:2864,errors:4,tokens:21000000,cost:24.1,share:.56},{name:'Codex',sub:'智能体',calls:1346,errors:6,tokens:11000000,cost:12.6,share:.26},{name:'Cursor',sub:'智能体',calls:728,errors:2,tokens:5800000,cost:4.5,share:.14}],
    models:[{name:'Claude · Sonnet',sub:'示例',calls:2864,errors:4,tokens:21000000,cost:24.1,share:.56,ttftMs:1900},{name:'GPT',sub:'示例',calls:1346,errors:6,tokens:11000000,cost:12.6,share:.26,ttftMs:3100},{name:'DeepSeek',sub:'示例',calls:728,errors:2,tokens:5800000,cost:4.5,share:.14,ttftMs:1400}]}};
}
function demoTick(){const agents=['claude','codex','cursor'],models=['sonnet','gpt','deepseek'],i=demoSeq++%3;const flow={id:'demo-'+demoSeq,agentID:agents[i],destinationID:models[(i+Math.floor(demoSeq/4))%3],stage:'incoming',outcome:demoSeq%9===0?'rateLimited':'ok',requestTokens:1800+demoSeq*237,responseTokens:460+demoSeq*71};spawn(flow);const p=flights.get(flow.id);if(p)p.demo=true;}
function sample(p,u,returning){const left=paths.get(p.a),right=paths.get(p.m);if(!left||!right)return hub.position.clone();if(returning)return u<.5?right.output.curve.getPoint(1-u*2):left.output.curve.getPoint(2-u*2);return u<.5?left.input.curve.getPoint(u*2):right.input.curve.getPoint(u*2-1);}
function screenPoint(point){const p=point.clone().project(camera);return {x:(p.x*.5+.5)*innerWidth,y:(-.5*p.y+.5)*innerHeight};}
function animateFlights(dt){
  let active=0;const load=new Map();
  for(const p of [...flights.values()]){
    if(!paths.has(p.a)||!paths.has(p.m)){removeFlight(p);continue;}
    if(p.demo&&p.age>4.6){p.done=true;p.flow.stage='returning';}
    if(!p.done&&time-p.lastSeen>100){removeFlight(p);continue;}
    p.age+=dt;if(!p.done&&p.age>=4.7)p.age=4.1;
    const returning=p.done&&p.age>=4.8;const travel=returning?(p.age-4.8)/3.8:Math.min(1,p.age/3.8);
    if(returning&&travel>1.15){removeFlight(p);continue;}
    const u=Math.max(0,Math.min(1,travel));const error=returning&&p.flow.outcome!=='ok';
    const color=new T.Color(error?C.error:returning?C.out:C.in);
    const point=sample(p,u,returning);p.group.position.copy(point);
    p.light.material.color.copy(color);p.light.scale.setScalar(1.9+Math.sin(time*9+p.age)*.25);
    p.ribbon.mesh.material.uniforms.color.value.copy(color);p.head.material.color.copy(color).lerp(new T.Color(C.white),.35);
    p.label.className='packet-label'+(error?' error':returning?' return':'');
    const n=returning?p.flow.responseTokens:p.flow.requestTokens;
    p.label.textContent=error?(p.flow.statusCode||p.flow.outcome==='rateLimited'&&'429'||'ERR')+' ↩':(returning?'OUT ':'IN ')+(n>0?compact(n)+' tok':'待计量');
    const sp=screenPoint(point);p.label.style.left=sp.x+'px';p.label.style.top=sp.y+'px';
    const waiting=!returning&&p.age>3.8;
    p.label.style.opacity=point.distanceTo(hub.position)<1.9?'0':waiting?'.55':'1';
    for(let j=0;j<p.count;j++){
      const back=Math.max(0,u-j*.0042);const pos=sample(p,back,returning);
      const spread=.03+j*.0016+Math.sin(j*.8+time*3)*.02;pos.y+=Math.sin(j*2.3+time*2)*spread;pos.z+=Math.cos(j*2.3+time*2)*spread;
      p.positions.set(pos.toArray(),j*3);
      const width=(.06+Math.log2(1+(n||0))*.0045)*(1-j/p.count);p.ribbon.positions.set([pos.x,pos.y-width,pos.z,pos.x,pos.y+width,pos.z],j*6);
      const bright=Math.pow(1-j/p.count,1.3);p.colors.set([color.r*bright,color.g*bright,color.b*bright],j*3);
    }
    p.ribbon.mesh.geometry.attributes.position.needsUpdate=true;p.trail.geometry.attributes.position.needsUpdate=true;p.trail.geometry.attributes.color.needsUpdate=true;
    for(const key of [p.a,p.m]){const route=paths.get(key);(returning?route.output:route.input).heat=1;}
    if(waiting){const m=nodes.get(p.m);if(m)m.busy=Math.min(1,m.busy+dt*2);}
    for(const [key,dirKey] of [[p.a,returning?'out':'in'],[p.m,returning?'out':'in']]){const l=load.get(key)||{in:0,out:0,n:0};l[dirKey]+=n||0;l.n++;load.set(key,l);}
    const leg=Math.floor(u*2)+(returning?2:0);
    if(p.lastLeg!==leg){
      if(p.lastLeg>=0){
        if(leg===1||leg===3)pulse(hub.position,color.getHex(),1.6);
        if(leg===2){const m=nodes.get(p.m);if(m){m.flash=1;pulse(m.group.position,C.in,1.2);}}
        if(leg===4){const a=nodes.get(p.a);if(a){a.flash=1;pulse(a.group.position,color.getHex(),1.2);}}
      }
      p.lastLeg=leg;
      if(returning)$('message').textContent=error?'异常已回传 · '+p.label.textContent:(nodes.get(p.m).name||'模型')+' → '+(nodes.get(p.a).name||'智能体');
    }
    active++;
  }
  for(const n of nodes.values()){const l=load.get(n.key);const text=l?'进行中 '+l.n+(l.in?' · ↑'+compact(l.in):'')+(l.out?' · ↓'+compact(l.out):''):'';if(text!==n.liveText){n.liveText=text;n.live.textContent=text;}}
  $('active').textContent=String(active);
  $('core-state').textContent=active?'TOKEN 传输中 · '+active+' 条光流':data.online?'本地智能路由 · 待机':'等待连接';
}
function animateNodes(dt){
  for(const n of [...nodes.values()]){
    const goal=n.leaving?0:1;
    n.appear=motion.matches?goal:goal?Math.min(1,n.appear+dt/1.1):Math.max(0,n.appear-dt/1.3);
    if(n.leaving&&n.appear<=0){removeNode(n);continue;}
    n.group.position.lerp(n.target,motion.matches?1:Math.min(1,dt*2.2));
    const s=Math.max(.001,motion.matches?n.appear:easeOutBack(n.appear));
    n.group.scale.setScalar(s*(1+n.flash*.35));
    n.busy=Math.max(0,n.busy-dt*.8);n.flash=Math.max(0,n.flash-dt*1.6);
    const spin=motion.matches?0:time;
    n.rings[0].rotation.z=spin*(.5+n.busy*3)+n.index;n.rings[1].rotation.z=-spin*(.8+n.busy*4)+n.index;
    n.shell.rotation.set(spin*.4,spin*(.6+n.busy*2.5),0);n.shell.scale.setScalar(1+n.busy*.18*Math.sin(time*7));
    n.light.material.opacity=(.26+n.flash*.55+n.busy*.25)*n.appear;
    // The arrival beam flares while the node materialises, then settles to a faint column.
    n.beam.material.opacity=((1-n.appear)*.9*(n.leaving?0:1)+.07+n.flash*.25)*Math.min(1,n.appear*4);
    n.beam.scale.y=7*(n.leaving?n.appear:1);
    n.label.style.opacity=String(Math.max(0,n.appear*1.2-.2).toFixed(2));
  }
  const any=nodes.size>0;$('empty').style.opacity=any?'0':'1';
}
function placeLabels(){for(const n of nodes.values()){const p=screenPoint(n.group.position),pad=n.side*Math.max(50,innerWidth*.027);n.label.style.left=(p.x+pad)+'px';n.label.style.top=p.y+'px';}const p=screenPoint(v3(0,-4,0));$('core-caption').style.top=p.y+'px';}
let lastClock='';
function tickClock(){const d=new Date(),t=String(d.getHours()).padStart(2,'0')+':'+String(d.getMinutes()).padStart(2,'0');if(t!==lastClock){lastClock=t;$('clock').textContent=t;if(d.getMinutes()===0&&data.dashboard)renderDashboard();}}
function frame(stamp){
  requestAnimationFrame(frame);if(document.hidden||stamp-lastFrame<(motion.matches?250:1000/30))return;
  const dt=lastFrame?Math.min((stamp-lastFrame)/1000,.1):0;lastFrame=stamp;if(!motion.matches)time+=dt;
  uniforms.time.value=time;energy=Math.max(0,energy-dt*.5);uniforms.energy.value=Math.min(1,energy);
  if(!motion.matches){disk.rotation.z=-.34+time*.035;dust.rotation.z=-time*(.09+energy*.05);rings.forEach((r,i)=>r.rotation.z=i*1.7+time*(i%2?.08:-.12));outer.rotation.y=.6+Math.sin(time*.16)*.08;stars.rotation.z=Math.sin(time*.02)*.008;halo.material.opacity=.33+energy*.14+Math.sin(time*.8)*.03;}
  for(let i=bursts.length-1;i>=0;i--){const b=bursts[i];b.age+=dt;b.mesh.scale.setScalar(1+b.age*4*b.scale);b.mesh.material.opacity=Math.max(0,.7-b.age*.7);if(b.age>1){dispose(b.mesh);bursts.splice(i,1);}}
  // Reduce Motion keeps the scene still while status and totals continue to update.
  // A finished request may release a node that only its returning light was holding.
  if(relayout){relayout=false;reconcile(data.online?data.agents||[]:[],-1);reconcile(data.online?data.models||[]:[],1);}
  animateNodes(dt);updatePaths(dt);
  if(!motion.matches){animateFlights(dt);if(preview){demoClock+=dt;if(demoClock>2.5){demoClock=0;demoTick();}}}
  else{$('active').textContent=String((data.flows||[]).filter(f=>f.stage!=='returning').length);for(const p of flights.values()){p.group.visible=false;p.trail.visible=false;p.ribbon.mesh.visible=false;p.label.style.display='none';}}
  if(!motion.matches&&Math.floor(time/15)%Math.max(1,Math.ceil((data.accounts||[]).length/3))!==accountPage)renderTelemetry();
  tickClock();placeLabels();renderer.render(scene,camera);
}
function resize(){
  camera.aspect=innerWidth/innerHeight;camera.position.z=camera.aspect<1.4?33:27;camera.updateProjectionMatrix();renderer.setSize(innerWidth,innerHeight);
  // Nodes sit a third of the way in from each side, clear of the dashboards.
  const halfWidth=camera.position.z*Math.tan(camera.fov*Math.PI/360)*camera.aspect;nodeX=halfWidth*(camera.aspect<1.5?.27:.33);
  for(const side of [-1,1]){const list=[...nodes.values()].filter(n=>n.side===side&&!n.leaving);list.forEach(n=>n.target.copy(slot(side,n.index,list.length)));}
  placeLabels();
}
window.addEventListener('resize',resize);document.addEventListener('visibilitychange',()=>lastFrame=0);
motion.addEventListener('change',()=>{for(const p of flights.values()){p.group.visible=!motion.matches;p.trail.visible=!motion.matches;p.ribbon.mesh.visible=!motion.matches;p.label.style.display=motion.matches?'none':'';}});
$('scene').addEventListener('webglcontextlost',event=>{event.preventDefault();$('failure').hidden=false;});$('scene').addEventListener('webglcontextrestored',()=>location.reload());
// Read-only diagnostics for render and flow regression checks.
window.magpieSceneState=()=>({preview,sceneTime:time,online:data.online,nodes:nodes.size,nodeList:[...nodes.values()].map(n=>({key:n.key,appear:n.appear,leaving:n.leaving,position:n.group.position.toArray()})),flights:[...flights.values()].map(p=>({id:p.id,returning:p.done,age:p.age,position:p.group.position.toArray(),visible:p.group.visible,requestTokens:p.flow.requestTokens,responseTokens:p.flow.responseTokens})),reducedMotion:motion.matches,renderCalls:renderer.info.render.calls});
resize();window.setMagpieData({...data,preview:query.has('demo')});requestAnimationFrame(frame);
})();
