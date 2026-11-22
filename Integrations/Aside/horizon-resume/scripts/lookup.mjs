import { spawnSync } from 'node:child_process';
import { join } from 'node:path';
import { homedir } from 'node:os';
const schema='horizon.aside.v1';function finish(status,handoff=''){process.stdout.write(JSON.stringify({schema,status,handoff})+'\n')}
let n=0,b=[];for await(const c of process.stdin){n+=c.length;if(n>8192){finish('invalid');process.exit(0)}b.push(c)}
let obj;try{obj=JSON.parse(Buffer.concat(b).toString('utf8'))}catch{};
if(!obj||Object.keys(obj).length!==1||typeof obj.query!=='string'||!obj.query.trim()){finish('invalid');process.exit(0)}
const app=join(homedir(),'Applications/contexta-horizon.app/Contents'),v=spawnSync('/usr/libexec/PlistBuddy',['-c','Print CFBundleShortVersionString',join(app,'Info.plist')],{encoding:'utf8'});const [major,minor]=(v.stdout||'').trim().split('.').map(Number);if(!(major>0||major===0&&minor>=5)){finish('unavailable');process.exit(0)}
const env={HOME:homedir(),PATH:'/usr/bin:/bin',LANG:'en_US.UTF-8'};const r=spawnSync(join(app,'MacOS/ContextaHorizon'),['--aside-lookup'],{input:JSON.stringify({query:obj.query}),encoding:'utf8',timeout:20000,maxBuffer:32768,env});let x;try{x=JSON.parse(r.stdout)}catch{};if(!x||x.schema!==schema||!['matched','no_match','invalid','unavailable'].includes(x.status)||typeof x.handoff!=='string'||x.status==='matched'&&!x.handoff.trim()){finish('unavailable')}else{finish(x.status,x.status==='matched'?x.handoff:'')}
