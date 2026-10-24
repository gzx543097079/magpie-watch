/* macOS host adapter for dsh-whale-musume. The original, unmodified MIT core
   supplies state priority, pose names and hit zones. The host supplies Magpie
   route events instead of querying DeepSeek Harness DOM. */
(() => {
  'use strict';
  const core = window.DshWhaleMoeCore;
  const art = document.getElementById('art'), pet = document.getElementById('pet');
  const motion = document.getElementById('motion'), status = document.getElementById('status');
  const bubble = document.getElementById('bubble'), particles = document.getElementById('particles');
  const media = matchMedia('(prefers-reduced-motion: reduce)');
  const outfits = {whale:'idle-cute',pajama:'daily-pajama',christmas:'festival-christmas',halloween:'festival-halloween',midAutumn:'festival-mid-autumn',spring:'festival-spring',valentine:'valentine'};
  const idlePoses = ['idle-cute','daily-coffee','daily-stretch','wink','tail-swing'];
  const busyStates = new Set(['tool','thinking','waiting']);
  const cache = new Map(), seenEvents = new Set();
  let skin = 'whale', hostState = 'idle', state = null, dragging = false, paused = false;
  let pose = 'idle-cute', requestedPose = pose, generation = 0, swapAnimation = null;
  let lastInteraction = Date.now(), successAt = -Infinity, failureUntil = 0;
  let reaction = null, nextIdle = Date.now()+14000, idleIndex = 0, bubbleUntil = 0;
  let preview = null, clickTimes = [];
  const path = name => `WhaleMusume/dsh-whale-state-${name}.webp`;
  function load(name) {
    if (!cache.has(name)) {
      const image = new Image();
      const promise = new Promise((resolve,reject) => {
        image.onload = () => resolve(image); image.onerror = reject; image.src = path(name);
      });
      cache.set(name,promise);
    }
    return cache.get(name);
  }
  function reduced() { return media.matches || paused; }
  function cancelMotion() { if(swapAnimation) { swapAnimation.cancel(); swapAnimation = null; } }
  async function setPose(next, immediate = false) {
    if (requestedPose === next && (!immediate || pose === next)) return;
    requestedPose = next;
    const gen = ++generation;
    cancelMotion();
    try { await load(next); } catch { if(gen === generation) requestedPose = pose; return; }
    if(gen !== generation) return;
    const commit = () => { art.src = path(next); pose = next; pet.dataset.pose = next; };
    if(immediate || reduced() || typeof motion.animate !== 'function') { commit(); return; }
    // Hide the image change at the compression point; never crossfade faces.
    swapAnimation = motion.animate([{transform:'translateY(0) scale(1)'},{transform:'translateY(10px) scale(.88,.93)'}],{duration:140,easing:'cubic-bezier(.55,0,1,.45)',fill:'forwards'});
    try { await Promise.race([swapAnimation.finished,new Promise(resolve=>setTimeout(resolve,800))]); } catch { return; }
    if(gen !== generation) return;
    cancelMotion(); commit();
    if(!reduced()) swapAnimation = motion.animate([{transform:'translateY(12px) scale(.9,.94)'},{transform:'translateY(-3px) scale(1.02,1.01)'},{transform:'none'}],{duration:440,easing:'cubic-bezier(.22,1,.36,1)'});
  }
  function say(text,duration=2600) {
    bubble.textContent = text; bubble.classList.add('show'); bubbleUntil = Date.now()+duration;
  }
  function burst(symbol='♥') {
    if(reduced()) return;
    for(let i=0;i<7;i++) {
      const spark = document.createElement('span'); spark.className='spark'; spark.textContent=i%2?symbol:'✦';
      spark.style.setProperty('--dx',`${(i-3)*15}px`);spark.style.setProperty('--spin',`${(i-3)*17}deg`);
      spark.style.color=i%2?'#ff9dbd':'#ffdf93';particles.appendChild(spark);
      setTimeout(()=>spark.remove(),1000);
    }
  }
  function react(next,text,symbol='♥',duration=2500) {
    reaction={pose:next,until:Date.now()+duration}; say(text,duration);burst(symbol);render(true);
  }
  function render(immediate=false) {
    if(paused) return;
    const now=Date.now(), source=preview && preview.until>now ? preview.state : hostState;
    if(preview && preview.until<=now) preview=null;
    state=core.computeState(state,{
      error:source==='failure' && (preview || failureUntil>now),
      tool:source==='tool',thinking:source==='thinking',waiting:source==='waiting',
      successAt:preview && source==='success'?now:successAt,lastInteraction
    },now);
    const busy=busyStates.has(state.state);
    pet.dataset.state=state.state;
    let next=state.pose || 'idle-cute';
    if(state.state==='idle') {
      if(now>=nextIdle) {idleIndex=(idleIndex+1)%idlePoses.length;nextIdle=now+(idleIndex===0?16000:5500);}
      next=skin==='whale'?idlePoses[idleIndex]:outfits[skin];
    }
    if(reaction && now>=reaction.until) reaction=null;
    if(reaction) next=reaction.pose;
    if(dragging) next='pick-up';
    const labels={idle:'陪伴中',afk:'打个盹，来单叫我',waiting:'请求排队中',thinking:'接收请求 · 思考中',tool:'抱紧电脑 · 工作中',success:'Token 已回流',failure:'请求出错 · 陪你排查'};
    status.textContent=(preview?'动作预览 · ':hostState==='offline'?'未连接 · ':'鲸鱼娘 · ')+(labels[state.state]||'陪伴中');
    if(now>=bubbleUntil) bubble.classList.remove('show');
    pet.dataset.busy=String(busy);setPose(next,immediate||dragging);
  }
  window.setPetSkin = next => {
    skin=Object.hasOwn(outfits,next)?next:'whale';idleIndex=0;nextIdle=Date.now()+16000;
    reaction=null;preview=null;render();
  };
  window.setPetState = (next,eventID='') => {
    if(!['idle','offline','waiting','thinking','tool','success','failure'].includes(next)) next='idle';
    const now=Date.now();
    if(eventID && !seenEvents.has(eventID)) {
      seenEvents.add(eventID);if(seenEvents.size>256) seenEvents.delete(seenEvents.values().next().value);
      if(next==='success') successAt=now;
      if(next==='failure') failureUntil=now+3200;
    }
    if(next==='offline') {successAt=-Infinity;failureUntil=0;reaction=null;}
    if(busyStates.has(next) && hostState!==next) {reaction=null;lastInteraction=now;}
    hostState=next;render();
  };
  window.setPetDrag = (active,delta=0) => {
    dragging=active;lastInteraction=Date.now();
    pet.classList.toggle('dragging',active);pet.style.setProperty('--tilt',`${Math.max(-12,Math.min(12,delta*.7))}deg`);
    if(active) {reaction=null;preview=null;bubble.classList.remove('show');}
    render(true);
  };
  window.petInteract = (action='pat',x=.5,y=.3) => {
    if(paused||dragging) return;
    lastInteraction=Date.now();preview=null;
    const busy=busyStates.has(hostState);
    if(action==='feed') react(busy?'work-ram':'eat',busy?'忙里吃一口，继续开工～':'啊呜！点心收到啦～','✦');
    else if(action==='praise') react('star','被夸奖啦！今天也要元气满满～','★');
    else if(action==='poke') react('react-belly','痒痒的，别闹啦～','✧');
    else {
      clickTimes=clickTimes.filter(t=>lastInteraction-t<1000);clickTimes.push(lastInteraction);
      if(clickTimes.length>=3){clickTimes=[];react('celebrate','三连摸头！快乐加倍～','★');}
      else if(busy) react('work-pat','有在认真工作哦～');
      else {const zone=core.hitZone(x,y,'full');react(`react-${zone}`,{head:'嘿嘿，再摸一下嘛～',belly:'小肚子不可以偷袭！',tail:'尾巴也想和你打招呼～'}[zone]);}
    }
  };
  window.previewPetState = next => {
    if(!['waiting','thinking','tool','success','failure','idle'].includes(next)) return;
    reaction=null;preview={state:next,until:Date.now()+5000};render();
  };
  window.setPetPaused = value => {
    paused=Boolean(value);document.body.classList.toggle('paused',paused);
    if(paused){generation++;cancelMotion();requestedPose=pose;particles.replaceChildren();}else render(true);
  };
  media.addEventListener('change',()=>{generation++;cancelMotion();requestedPose=pose;document.body.classList.toggle('reduced',media.matches);render(true);});
  document.addEventListener('visibilitychange',()=>window.setPetPaused(document.hidden));
  window.magpiePetState=()=>({skin,hostState,state:state?.state,pose,requestedPose,dragging,paused,preview:Boolean(preview),reducedMotion:media.matches});
  ['idle-cute','running','pick-up','react-head','thinking',...Object.values(outfits),'success','failure','eat','star','work-pat','work-ram','react-belly','react-tail','celebrate','waiting','afk',...idlePoses].forEach(name=>load(name).catch(()=>{}));
  setInterval(render,500);render();
})();
