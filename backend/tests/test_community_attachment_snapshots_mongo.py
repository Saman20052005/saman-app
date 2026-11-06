"""Real standalone-Mongo attachment projection/ownership/immutable replay."""
import os,uuid,unittest
from datetime import datetime,timezone,timedelta
from concurrent.futures import ThreadPoolExecutor
from unittest.mock import patch
os.environ.update(MONGO_URI='mongodb://127.0.0.1:27048',DB_NAME='saman_jcom0509_test_import',LOG_AUTH_HEADER='0')
import jwt
from bson import ObjectId
from pymongo import MongoClient
from fastapi import FastAPI
from fastapi.testclient import TestClient
from backend.routers import community as r
from backend.scripts.setup_community_attachment_indexes import setup_indexes,validate_target

class AttachmentMongoTest(unittest.TestCase):
 @classmethod
 def setUpClass(cls):
  cls.name='saman_jcom0509_test_'+uuid.uuid4().hex;validate_target(os.environ['MONGO_URI'],cls.name)
  cls.mongo=MongoClient(os.environ['MONGO_URI']);cls.db=cls.mongo[cls.name];setup_indexes(cls.db)
  app=FastAPI();app.include_router(r.router);cls.app=app
 @classmethod
 def tearDownClass(cls):cls.mongo.close()
 def setUp(self):
  self.a='a_'+uuid.uuid4().hex;self.b='b_'+uuid.uuid4().hex
  for uid in [self.a,self.b]:self.db.users.insert_one({'_id':uid,'email':uid+'@example.com','name':'Owner','password':'private','health_stats':{'weight':70}})
  self.auth={uid:{'Authorization':'Bearer '+jwt.encode({'email':uid+'@example.com','exp':datetime.now(timezone.utc)+timedelta(minutes=15)},r.JWT_SECRET,algorithm=r.JWT_ALGORITHM)} for uid in [self.a,self.b]}
  p=patch.object(r,'db',self.db);p.start();self.addCleanup(p.stop);self.client=TestClient(self.app);self.addCleanup(self.client.close)
  self.ids={}
  self.ids['workout']=str(self.db.workout_history.insert_one({'user_id':self.a,'email':self.a+'@example.com','plan_name':'Strength','date':'2026-11-03','finished_at':datetime.now(timezone.utc),'total_duration_minutes':42,'total_volume_kg':800,
   'notes':'never share','exercise_logs':[{'exercise_id':'private-id','exercise_slug':'bench-press','set_number':1,'weight_kg':40,'reps_completed':10,'cv_detected':True}]}).inserted_id)
  self.ids['meal']=str(self.db.nutrition_plans.insert_one({'user_email':self.a+'@example.com','meal_type':'Lunch','date':'2026-11-03','notes':'never share','total_calories':500,'total_protein':35,'total_carbs':45,'total_fat':20,
   'foods':[{'name':'Rice','food_id':'private-food','weight_grams':200,'calories':300,'protein':12}]}).inserted_id)
 def preview(self,kind='workout',uid=None,**opts):
  return self.client.get('/api/community/attachment-sources/'+kind+'/'+self.ids[kind],headers=self.auth[uid or self.a],params=dict(include_duration=kind=='workout',**opts))
 def body(self,kind='workout',**opts):
  p=self.preview(kind,**opts);self.assertEqual(p.status_code,200,p.text);v=p.json()
  return {'type':kind,'content':'Shared','privacy':'public','topic':'#ChiaSẻ','attachment':{'source_id':v['source_id'],'preview_hash':v['preview_hash'],'include_duration':kind=='workout','include_exercises_or_foods':opts.get('include_exercises_or_foods',True),'include_load_or_macros':opts.get('include_load_or_macros',False)}}
 def send(self,body,key=None,uid=None):return self.client.post('/api/community/posts',headers=dict(self.auth[uid or self.a],**{'X-Idempotency-Key':key or uuid.uuid4().hex}),json=body)
 def test_defaults_omitted_nested_fields_and_safe_viewer_projection(self):
  for kind in self.ids:
   body=self.body(kind);response=self.send(body);self.assertEqual(response.status_code,200,response.text);post=response.json();snap=post['attachment_snapshot']
   self.assertEqual(post['type'],kind);self.assertEqual(post['author']['id'],self.a)
   for key in ['source_id','preview_hash','set_count','load_kg','calories','protein_grams','carbs_grams','fat_grams','notes','user_email','exercise_id','food_id','cv_detected','weight_kg']:
    self.assertNotIn('"'+key+'"',__import__('json').dumps(snap))
   stored=self.db.community_posts.find_one({'_id':ObjectId(post['id'])});self.assertEqual(stored['attachment_snapshot'],snap)
   public=self.client.get('/api/community/posts/'+post['id'],headers=self.auth[self.b]).json();self.assertEqual(public['attachment_snapshot'],snap)
   self.assertNotIn('publication_payload',public)
 def test_switches_omit_fields_and_sensitive_opt_in(self):
  for kind in self.ids:
   post=self.send(self.body(kind,include_exercises_or_foods=False)).json();snap=post['attachment_snapshot'];self.assertNotIn('exercises',snap);self.assertNotIn('foods',snap);self.assertNotIn('exercise_count',snap)
   post=self.send(self.body(kind,include_load_or_macros=True)).json();snap=post['attachment_snapshot']
   self.assertEqual(snap['set_count'] if kind=='workout' else snap['calories'],1 if kind=='workout' else 500)
  preview=self.client.get('/api/community/attachment-sources/workout/'+self.ids['workout'],headers=self.auth[self.a],params={'include_duration':False}).json();self.assertNotIn('duration_minutes',preview['snapshot'])
 def test_foreign_unfinished_deleted_and_validation(self):
  for kind in self.ids:
   self.assertEqual(self.preview(kind,self.b).status_code,404)
   listed=self.client.get('/api/community/attachment-sources/'+kind,headers=self.auth[self.b]).json()['items'];self.assertEqual(listed,[])
   self.assertEqual(self.send(self.body(kind),uid=self.b).status_code,404)
  body=self.body();body['attachment']['weight_kg']=100;self.assertEqual(self.send(body).status_code,422)
  body=self.body();body['attachment']['include_load_or_macros']='true';self.assertEqual(self.send(body).status_code,422)
  self.db.workout_history.update_one({'_id':ObjectId(self.ids['workout'])},{'$set':{'finished_at':None}});self.assertEqual(self.preview().status_code,404)
 def test_changed_shared_preview_rejected_before_insert_but_hidden_change_allowed(self):
  body=self.body();self.db.workout_history.update_one({'_id':ObjectId(self.ids['workout'])},{'$set':{'total_duration_minutes':99}})
  self.assertEqual(self.send(body).status_code,409);self.assertEqual(self.db.community_posts.count_documents({'user_id':self.a}),0)
  body=self.body();self.db.workout_history.update_one({'_id':ObjectId(self.ids['workout'])},{'$set':{'total_volume_kg':99999}});self.assertEqual(self.send(body).status_code,200)
 def test_lost_response_source_changed_or_deleted_retry_same_frozen_snapshot(self):
  for kind in self.ids:
   body=self.body(kind);key=uuid.uuid4().hex;first=self.send(body,key).json()
   col=self.db.workout_history if kind=='workout' else self.db.nutrition_plans
   col.update_one({'_id':ObjectId(self.ids[kind])},{'$set':{'plan_name':'Changed','meal_type':'Changed','total_duration_minutes':999,'total_calories':999,'is_deleted':True}})
   retry=self.send(body,key);self.assertEqual(retry.status_code,200,retry.text);self.assertEqual(retry.json(),first)
   changed=dict(body,content='other');self.assertEqual(self.send(changed,key).status_code,409)
   self.assertEqual(self.db.community_posts.count_documents({'user_id':self.a,'request_key':key}),1)
   self.db.community_posts.update_one({'_id':ObjectId(first['id'])},{'$set':{'status':'draft'}})
   denied=self.send(body,key);self.assertEqual(denied.status_code,404);self.assertEqual(set(denied.json()),{'detail'})
 def test_concurrent_same_key_and_fresh_connection_private_audience(self):
  for kind in self.ids:
   body=self.body(kind);body['privacy']='private';key=uuid.uuid4().hex
   with ThreadPoolExecutor(max_workers=8) as pool:results=list(pool.map(lambda _:self.send(body,key),range(12)))
   self.assertTrue(all(x.status_code==200 for x in results));self.assertEqual(len({x.json()['id'] for x in results}),1)
   pid=results[0].json()['id'];self.assertEqual(self.client.get('/api/community/posts/'+pid,headers=self.auth[self.b]).status_code,404)
   with MongoClient('mongodb://127.0.0.1:27048') as fresh:self.assertEqual(fresh[self.name].community_posts.count_documents({'request_key':key}),1)

if __name__=='__main__':unittest.main()
