"""JCOM0508 standalone MongoDB text publishing and durable replay contract."""
import os
import uuid
import unittest
from datetime import datetime,timezone,timedelta
from concurrent.futures import ThreadPoolExecutor
from unittest.mock import patch
os.environ['MONGO_URI']='mongodb://127.0.0.1:27048'
os.environ['DB_NAME']='saman_jcom0508_test_import'
os.environ['LOG_AUTH_HEADER']='0'
from pymongo import MongoClient
from bson import ObjectId
from fastapi import FastAPI
from fastapi.testclient import TestClient
import jwt
from backend.routers import community as r
from backend.scripts.setup_community_publish_indexes import setup_indexes,validate_target


class PublishMongoTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.name='saman_jcom0508_test_'+uuid.uuid4().hex
        uri='mongodb://127.0.0.1:27048'; validate_target(uri,cls.name)
        cls.mongo=MongoClient(uri,serverSelectionTimeoutMS=2000); cls.mongo.admin.command('ping')
        cls.db=cls.mongo[cls.name]; setup_indexes(cls.db)
        cls.app=FastAPI(); cls.app.include_router(r.router)
    @classmethod
    def tearDownClass(cls):cls.mongo.close()
    def setUp(self):
        self.a='a_'+uuid.uuid4().hex; self.b='b_'+uuid.uuid4().hex
        for uid in [self.a,self.b]:self.db.users.insert_one({'_id':uid,'email':uid+'@example.com','name':'Canonical '+uid[0],
            'password':'synthetic-private','health_stats':{'weight':70},'is_verified':False})
        p=patch.object(r,'db',self.db); p.start(); self.addCleanup(p.stop)
        self.client=TestClient(self.app); self.addCleanup(self.client.close)
        self.auth={uid:{'Authorization':'Bearer '+jwt.encode({'email':uid+'@example.com',
            'exp':datetime.now(timezone.utc)+timedelta(minutes=10)},r.JWT_SECRET,algorithm=r.JWT_ALGORITHM)} for uid in [self.a,self.b]}
    def send(self,key=None,uid=None,**extra):
        body=dict(type='text',content='Canonical publication',privacy='public',topic='#ChiaSẻ'); body.update(extra)
        return self.client.post('/api/community/posts',headers=dict(self.auth[uid or self.a],**{'X-Idempotency-Key':key or uuid.uuid4().hex}),json=body)
    def detail(self,pid,uid=None):return self.client.get('/api/community/posts/'+pid,headers=self.auth[uid or self.a])
    def test_auth_canonical_projection_validation_and_unsupported_fields(self):
        self.assertEqual(self.client.post('/api/community/posts',json={'type':'text'}).status_code,401)
        for content in ['', '  ', 'x'*5001]:self.assertEqual(self.send(content=content).status_code,422)
        for field in ['author','author_id','created_at','status','like_count','media_urls','photo_urls','attachment','workout_attachment','nutrition_info','is_verified']:
            self.assertEqual(self.send(**{field:True}).status_code,422)
        self.assertEqual(self.send(type='photo').status_code,422)
        self.assertEqual(self.send(privacy='friends').status_code,422)
        self.assertEqual(self.send(topic='unknown').status_code,422)
        result=self.send(content='  canonical  '); self.assertEqual(result.status_code,200)
        post=result.json(); self.assertEqual(post['caption'],'canonical'); self.assertEqual(post['type'],'text')
        self.assertEqual(post['author']['id'],self.a); self.assertEqual(post['author']['name'],'Canonical a')
        self.assertFalse(post['author']['is_verified']); self.assertFalse({'password','email','health_stats','tokens'} & set(post['author']))
        self.assertEqual(post['photo_urls'],[]); self.assertIsNone(post['workout_attachment'])
        self.assertEqual(post['like_count'],0); self.assertEqual(post['comment_count'],0)
    def test_replay_concurrency_conflict_and_fresh_connection(self):
        key=uuid.uuid4().hex; initial=self.send(key=key); self.assertEqual(initial.status_code,200)
        with ThreadPoolExecutor(max_workers=8) as pool:results=list(pool.map(lambda _:self.send(key=key),range(16)))
        self.assertTrue(all(x.status_code==200 for x in results)); ids={x.json()['id'] for x in results}
        self.assertEqual(ids,{initial.json()['id']}); self.assertEqual(self.db.community_posts.count_documents({'user_id':self.a}),1)
        for change in [{'content':'different'},{'privacy':'private'},{'topic':'#Mẹo'},{'allow_comments':False}]:self.assertEqual(self.send(key=key,**change).status_code,409)
        fresh=MongoClient('mongodb://127.0.0.1:27048'); self.addCleanup(fresh.close)
        self.assertEqual(fresh[self.name].community_posts.count_documents({'user_id':self.a}),1)
    def test_audience_feed_detail_and_reverse_follow_not_enough(self):
        public=self.send().json(); private=self.send(privacy='private').json(); followers=self.send(privacy='followers_only').json()
        for post in [public,private,followers]:self.assertEqual(self.detail(post['id']).status_code,200)
        self.assertEqual(self.detail(public['id'],self.b).status_code,200)
        self.assertEqual(self.detail(private['id'],self.b).status_code,404)
        self.assertEqual(self.detail(followers['id'],self.b).status_code,404)
        self.db.community_follows.insert_one({'follower_id':self.a,'following_id':self.b})
        self.assertEqual(self.detail(followers['id'],self.b).status_code,404)
        self.db.community_follows.insert_one({'follower_id':self.b,'following_id':self.a})
        self.assertEqual(self.detail(followers['id'],self.b).status_code,200)
        feed=self.client.get('/api/community/feed',headers=self.auth[self.b]).json()['items']
        ids={p['id'] for p in feed}; self.assertIn(public['id'],ids); self.assertIn(followers['id'],ids); self.assertNotIn(private['id'],ids)
    def test_deleted_unpublished_replay_never_resurrects(self):
        for change in [{'is_deleted':True},{'status':'draft'},{'status':'unpublished'},{'status':None}]:
            key=uuid.uuid4().hex; post=self.send(key=key).json()
            self.db.community_posts.update_one({'_id':ObjectId(post['id'])},{'$set':change})
            response=self.send(key=key); self.assertEqual(response.status_code,404); self.assertEqual(set(response.json()),{'detail'})
            self.assertEqual(self.db.community_posts.count_documents({'user_id':self.a,'request_key':key}),1)
    def test_revoked_owner_and_deleted_identity_replay_no_payload(self):
        key=uuid.uuid4().hex; post=self.send(key=key,privacy='private').json()
        self.db.community_posts.update_one({'_id':ObjectId(post['id'])},{'$set':{'author_id':self.b,'author.id':self.b}})
        response=self.send(key=key,privacy='private'); self.assertEqual(response.status_code,404); self.assertEqual(set(response.json()),{'detail'})
        self.db.users.update_one({'_id':self.a},{'$set':{'email':'revoked_'+self.a+'@example.com'}})
        self.assertEqual(self.send(key=key).status_code,401)
    def test_response_loss_and_disabled_comments_are_persisted(self):
        key=uuid.uuid4().hex; self.send(key=key,allow_comments=False)
        retry=self.send(key=key,allow_comments=False); pid=retry.json()['id']
        self.assertFalse(self.db.community_posts.find_one({'_id':ObjectId(pid)})['allow_comments'])
        self.assertEqual(self.detail(pid).json()['id'],pid)
        response=self.client.post('/api/community/posts/'+pid+'/comments',headers=dict(self.auth[self.a],**{'X-Idempotency-Key':uuid.uuid4().hex}),json={'content':'blocked'})
        self.assertEqual(response.status_code,409)
    def test_missing_index_fails_closed(self):
        empty=self.mongo['saman_jcom0508_test_'+uuid.uuid4().hex]
        empty.users.insert_one(self.db.users.find_one({'_id':self.a}))
        with patch.object(r,'db',empty):self.assertEqual(self.send().status_code,503)
        self.assertEqual(empty.community_posts.count_documents({}),0)

    def qa(self,key=None,uid=None,**changes):
        body=dict(type='qa',title='  Canonical question?  ',body='  Optional context  ',privacy='public',topic='Dinh dưỡng')
        body.update(changes)
        return self.client.post('/api/community/posts',headers=dict(self.auth[uid or self.a],**{'X-Idempotency-Key':key or uuid.uuid4().hex}),json=body)

    def test_question_validation_canonical_and_detail(self):
        response=self.qa(); self.assertEqual(response.status_code,200,response.text)
        q=response.json(); self.assertEqual(q['type'],'qa'); self.assertEqual(q['author']['id'],self.a); self.assertEqual(q['caption'],'')
        self.assertEqual(q['qa_info']['question'],'Canonical question?'); self.assertEqual(q['qa_info']['details'],'Optional context')
        self.assertEqual(q['qa_info']['respondent_count'],0)
        self.assertNotIn('email',q['author']); self.assertEqual(self.detail(q['id']).json()['qa_info'],q['qa_info'])
        self.assertEqual(self.qa(body='').status_code,200)
        for change in [dict(title='   '),dict(title='x'*151),dict(body='x'*2001),dict(topic='unknown'),dict(privacy='friends'),dict(author_id=self.b),dict(media_urls=['x']),dict(status='published'),dict(attachment={}),dict(type='text')]:
            self.assertEqual(self.qa(**change).status_code,422,change)

    def test_question_same_key_concurrent_fresh_connection_and_cross_type_conflict(self):
        key=uuid.uuid4().hex
        with ThreadPoolExecutor(max_workers=8) as pool: responses=list(pool.map(lambda _:self.qa(key),range(16)))
        self.assertTrue(all(x.status_code==200 for x in responses)); ids={x.json()['id'] for x in responses}; self.assertEqual(len(ids),1)
        self.assertEqual(self.db.community_posts.count_documents({'user_id':self.a,'request_key':key}),1)
        self.assertEqual(self.qa(key,title='changed').status_code,409); self.assertEqual(self.send(key=key).status_code,409)
        with MongoClient('mongodb://127.0.0.1:27048') as fresh:
            self.assertEqual(fresh[self.name].community_posts.find_one({'request_key':key})['status'],'published')

    def test_question_audience_feed_and_revocation_before_replay(self):
        public=self.qa().json(); private=self.qa(privacy='private').json(); follower=self.qa(privacy='followers_only').json()
        feed=lambda: self.client.get('/api/community/feed?tab=qa',headers=self.auth[self.b]).json()['items']
        ids={x['id'] for x in feed()}; self.assertIn(public['id'],ids); self.assertNotIn(private['id'],ids); self.assertNotIn(follower['id'],ids)
        self.assertEqual(self.detail(private['id'],self.b).status_code,404)
        self.db.community_follows.insert_one({'follower_id':self.a,'following_id':self.b})
        self.assertEqual(self.detail(follower['id'],self.b).status_code,404)
        rel=self.db.community_follows.insert_one({'follower_id':self.b,'following_id':self.a})
        self.assertIn(follower['id'],{x['id'] for x in feed()})
        self.db.community_follows.update_one({'_id':rel.inserted_id},{'$set':{'following_id':'revoked'}})
        denied=self.detail(follower['id'],self.b);self.assertEqual(denied.status_code,404);self.assertEqual(set(denied.json()),{'detail'})
        key=uuid.uuid4().hex; post=self.qa(key).json();self.db.community_posts.update_one({'_id':ObjectId(post['id'])},{'$set':{'status':'draft'}})
        for title in ['Canonical question?','different']:
            denied=self.qa(key,title=title);self.assertEqual(denied.status_code,404);self.assertEqual(set(denied.json()),{'detail'})
        self.assertEqual(self.db.community_posts.count_documents({'request_key':key}),1)

if __name__=='__main__':unittest.main()
