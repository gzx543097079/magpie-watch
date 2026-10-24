import fs from 'node:fs/promises';
import vm from 'node:vm';
import assert from 'node:assert/strict';

export async function runPetRegression() {
  const root = new URL('../../', import.meta.url);
  const [core, adapter, manifestText] = await Promise.all([
    fs.readFile(new URL('Resources/Pets/WhaleMusume/whale-moe-core.js',root),'utf8'),
    fs.readFile(new URL('design/pet.js',root),'utf8'),
    fs.readFile(new URL('Resources/Pets/WhaleMusume/manifest.json',root),'utf8')
  ]);
  const assets = new Set(JSON.parse(manifestText).files.map(x=>'WhaleMusume/'+x.file));
  let now = 10000, timerID = 0, missing = [];
  const timers = new Map();
  const media = {matches:true, addEventListener(_,fn){this.changed=fn;}};
  class Element {
    constructor(){this.dataset={};this.children=[];this.style={setProperty(){}};this.classes=new Set();this.classList={add:x=>this.classes.add(x),remove:x=>this.classes.delete(x),toggle:(x,v)=>v?this.classes.add(x):this.classes.delete(x)};}
    appendChild(el){this.children.push(el);el.parent=this;}
    remove(){if(this.parent)this.parent.children=this.parent.children.filter(x=>x!==this);}
    replaceChildren(){this.children=[];}
    animate(){return {finished:Promise.resolve(),cancel(){}};}
  }
  const nodes=Object.fromEntries(['art','pet','motion','status','bubble','particles'].map(id=>[id,new Element()]));
  const document={hidden:false,body:new Element(),getElementById:id=>nodes[id],createElement:()=>new Element(),addEventListener(){}};
  const schedule=(fn,ms,repeat)=>{const id=++timerID;timers.set(id,{fn,at:now+ms,repeat:repeat?ms:0});return id;};
  const context={document,matchMedia:()=>media,Date:class extends Date {static now(){return now;}},Image:class {
    set src(path){if(!assets.has(path)){missing.push(path);Promise.resolve().then(()=>this.onerror?.());}else Promise.resolve().then(()=>this.onload?.());}
  },setTimeout:(fn,ms)=>schedule(fn,ms,false),setInterval:(fn,ms)=>schedule(fn,ms,true),clearTimeout:id=>timers.delete(id)};
  context.window=context;
  vm.createContext(context);vm.runInContext(core,context);vm.runInContext(adapter,context);
  const settle=async()=>{for(let i=0;i<12;i++)await Promise.resolve();};
  const advance=async ms=>{now+=ms;for(const [id,timer]of [...timers])if(timer.at<=now){if(timer.repeat)timer.at=now+timer.repeat;else timers.delete(id);timer.fn();}await settle();};
  const state=()=>context.magpiePetState();
  await settle();
  for(const skin of ['whale','pajama','christmas','halloween','midAutumn','spring','valentine']) {
    context.setPetSkin(skin);await settle();assert.equal(state().skin,skin);assert.ok(assets.has('WhaleMusume/dsh-whale-state-'+state().pose+'.webp'));
  }
  context.setPetSkin('whale');context.setPetState('tool');await settle();
  assert.equal(state().pose,'running');await advance(40000);assert.equal(state().pose,'running','idle timer must not replace active work');
  context.setPetDrag(true,8);await settle();assert.equal(state().pose,'pick-up');
  context.setPetDrag(false);await settle();assert.equal(state().pose,'running');
  context.petInteract('pat',.5,.3);await settle();assert.equal(state().pose,'work-pat');
  await advance(2600);assert.equal(state().pose,'running');
  context.setPetState('idle');
  context.petInteract('pat',.5,.2);await settle();assert.equal(state().pose,'react-head');
  await advance(1100);context.petInteract('pat',.5,.6);await settle();assert.equal(state().pose,'react-belly');
  await advance(1100);context.petInteract('pat',.5,.9);await settle();assert.equal(state().pose,'react-tail');
  context.petInteract('feed');await settle();assert.equal(state().pose,'eat');
  context.petInteract('praise');await settle();assert.equal(state().pose,'star');
  await advance(3000);
  context.setPetState('success','request-1');await settle();assert.equal(state().pose,'success');
  await advance(2500);context.setPetState('success','request-1');await settle();assert.equal(state().state,'idle','polling the same completion must not replay');
  context.setPetState('failure','request-2');await settle();assert.equal(state().pose,'failure');
  await advance(3500);assert.equal(state().state,'idle');
  context.setPetState('offline');await settle();assert.ok(nodes.status.textContent.includes('未连接'));
  context.previewPetState('tool');await settle();assert.equal(state().pose,'running');assert.ok(nodes.status.textContent.includes('预览'));
  await advance(5500);assert.equal(state().preview,false);assert.equal(state().hostState,'offline');
  // Cancel an in-flight pose load by hiding; resume must commit the requested pose.
  media.matches=false;media.changed();context.setPetState('thinking');context.setPetPaused(true);await settle();
  assert.equal(state().paused,true);context.setPetPaused(false);await settle();assert.equal(state().pose,'thinking');
  context.setPetDrag(true);context.setPetState('tool');context.setPetDrag(false);await settle();assert.equal(state().pose,'running','new work wins over an old image load');
  media.matches=true;media.changed();context.petInteract('praise');await settle();assert.equal(nodes.particles.children.length,0);assert.equal(state().reducedMotion,true);
  assert.deepEqual(missing,[],'every referenced asset must be bundled');
  return {passed:true,outfits:7,checks:['original core and assets','work/idle priority','drag and release','three hit zones','feed and praise','completion deduplication','failure expiry','offline','preview isolation','pause and stale load recovery','Reduce Motion']};
}
if(typeof process!=='undefined' && process.argv[1] && import.meta.url===new URL('file://'+process.argv[1]).href) console.log(await runPetRegression());
