#!/usr/bin/env python3
"""Development-only process/UI double. Not a Hub or backend acceptance harness."""
import sys,json,pathlib,uuid,datetime,copy
args=sys.argv[1:]
metrics=['summary.verdict','observers.verdicts','attention.list','applications.list','server.card','servers.list','sources.status','resource.cpu.used_percent','resource.memory.used_percent','resource.disk.used_percent']
if '--capabilities' in args:
 print(json.dumps({'protocol':1,'version':'D1-development-double','sources':['client','preview','direct'],'metrics':[{'name':m,'sources':['client','preview','direct']} for m in metrics],'direct':{'schema':1,'config_api':1,'adapters':['beszel'],'retry':True,'limits':{'sources_per_profile':64,'objects_per_source':20,'objects_per_profile':256,'template_rows':128}}}));sys.exit()
root=pathlib.Path(args[args.index('--direct-root')+1]) if '--direct-root' in args else None
if root is None:sys.exit(2)
statefile=root/'ui-double.json'
def load():return json.loads(statefile.read_text()) if statefile.exists() else {'profiles':[]}
def stamp(seconds=0):return (datetime.datetime.now(datetime.timezone.utc)+datetime.timedelta(seconds=seconds)).isoformat(timespec='seconds').replace('+00:00','Z')
systems=[{'id':'000000000000001','name':'Synthetic server 合成サーバー'},{'id':'000000000000002','name':'Synthetic secondary'}]
if args and args[0]=='sources':
 command=args[1];request=json.load(sys.stdin) if command!='list' else {};requestid=request.get('request_id','')
 def reply(data=None,code=None):
  print(json.dumps({'schema':1,'request_id':requestid,'ok':code is None,**({'error':{'code':code,'message':'Synthetic failure','retryable':False}} if code else {'data':data})}));sys.exit(1 if code else 0)
 state=load();profile=next((p for p in state['profiles'] if p['profile']==request.get('profile')),None)
 if command=='list':reply(state)
 source=request.get('source')
 if source and 'denied' in source['url']:reply(code='forbidden')
 if command=='inspect':reply({'source':source,'systems':systems,'truncated':False,'limits':{'max_selected':20},'warnings':[]})
 if profile and request.get('base_revision')!=profile['profile_revision']:reply(code='profile_conflict')
 if command=='save':
  if not request['selected_objects']:reply(code='selection_invalid')
  if profile is None:
   profile={'profile':request['profile'],'project':'Synthetic direct','profile_revision':'','dataset_id':str(uuid.uuid4()),'sources':[]};state['profiles'].append(profile)
  nodes=[{'id':source['id']+'.'+s['id'],'object_id':s['id'],'name':s['name']} for s in systems if s['id'] in request['selected_objects']]
  entry={'source':source,'auth_mode':'password' if request['auth']['mode']=='password' else 'token','selected_objects':request['selected_objects'],'nodes':nodes}
  profile['sources']=[e for e in profile['sources'] if e['source']['id']!=source['id']]+[entry]
  profile['profile_revision']=str(uuid.uuid4());profile['dataset_id']=str(uuid.uuid4())
  root.mkdir(parents=True,exist_ok=True);statefile.write_text(json.dumps(state))
  reply({k:profile[k] for k in ['profile','profile_revision','dataset_id']}|{'source_id':source['id'],'nodes':nodes})
 if command=='remove':
  if profile is None:reply(code='profile_not_found')
  profile['sources']=[e for e in profile['sources'] if e['source']['id']!=request['source_id']]
  profile['profile_revision']=str(uuid.uuid4());profile['dataset_id']=str(uuid.uuid4());statefile.write_text(json.dumps(state))
  reply({k:profile[k] for k in ['profile','profile_revision','dataset_id']}|{'source_id':request['source_id']})
 sys.exit(2)
if args[:2]==['monitor','stream']:
 instance=str(uuid.uuid4());seq=0
 for line in sys.stdin:
  r=json.loads(line);state=load();p=next((p for p in state['profiles'] if p['profile']==r.get('profile')),None)
  if p is None:
   print(json.dumps({'schema':1,'request_id':r['request_id'],'lifecycle':'error','error':{'code':'profile_not_found','message':'Synthetic profile missing'},'rows':[]}),flush=True);continue
  f=json.loads((pathlib.Path(__file__).parent/'ready.json').read_text());seq+=1
  f.update(request_id=r['request_id'],instance=instance,sequence=seq,profile=p['profile'],profile_revision=p['profile_revision'],dataset_id=p['dataset_id'],generated_at=stamp(),publisher_expires_at=stamp(30))
  origins={};nodes=[];sources=[]
  for e in p['sources']:
   for n in e['nodes']:
    origins[n['id']]={'adapter':'beszel','source_id':e['source']['id'],'name':e['source']['name'],'object_id':n['object_id']};nodes.append(n)
   sources.append({'id':e['source']['id'],'name':e['source']['name'],'adapter':'beszel','state':'connected','counts':{'selected':len(e['nodes']),'current':len(e['nodes']),'stale':0,'missing':0},'last_attempt_at':stamp(),'last_contact_at':stamp(),'contact_valid_until':stamp(180),'next_retry_at':None,'code':None})
  rows=[]
  for t in r['template']['rows']:
   row=copy.deepcopy(t);row.update(health='unknown',valid_until=stamp(180),sampled_at=stamp())
   if t['metric']=='sources.status':row.update(health='up',value={'state':'ready' if nodes else 'no_data','counts':{'sources':len(sources),'selected':len(nodes),'current':len(nodes),'stale':0,'missing':0,'attention':0},'sources':sources})
   elif t['metric']=='servers.list':row['value']=[{'id':n['id'],'name':n['name'],'kind':'host','provider':'','where':'','health':'unknown','origin':origins[n['id']]} for n in nodes]
   elif t['metric']=='server.card':
    n=next((n for n in nodes if n['id']==t['select']['node']),None)
    card=copy.deepcopy(f['rows'][-1]['value']);card.update(id=n['id'],name=n['name'],origin=origins[n['id']]) if n else None
    if n:
     card['resources'][0].update(origin=origins[n['id']],sampled_at=stamp(-10),valid_until=stamp(170));row['value']=card
    else:row.update(value=None,reason='entity_missing')
   else:row['value']=None
   rows.append(row)
  f['rows']=rows;print(json.dumps(f),flush=True)
