"""Real standalone MongoDB answer/vote contract tests; retained isolated data."""
import os
import uuid
import unittest
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone, timedelta
from unittest.mock import patch
os.environ['MONGO_URI']='mongodb://127.0.0.1:27046'
os.environ['DB_NAME']='saman_jcom0507_test_import'
os.environ['LOG_AUTH_HEADER']='0'
from pymongo import MongoClient
from fastapi import FastAPI
from fastapi.testclient import TestClient
import jwt
from backend.routers import community as r
from backend.scripts.setup_community_answer_indexes import setup_indexes, validate_target


class AnswersMongoTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.name='saman_jcom0507_test_'+uuid.uuid4().hex
        uri='mongodb://127.0.0.1:27046'; validate_target(uri,cls.name)
        cls.mongo=MongoClient(uri,serverSelectionTimeoutMS=2000); cls.mongo.admin.command('ping')
        cls.db=cls.mongo[cls.name]; setup_indexes(cls.db)
        cls.app=FastAPI(); cls.app.include_router(r.router)

    @classmethod
    def tearDownClass(cls): cls.mongo.close()

    def setUp(self):
        self.q='q_'+uuid.uuid4().hex; self.a='a_'+uuid.uuid4().hex; self.b='b_'+uuid.uuid4().hex
        for uid in [self.a,self.b]:
            self.db.users.insert_one({'_id':uid,'email':uid+'@example.com','name':'Canonical '+uid[0],
                'password':'synthetic-private','health_stats':{'weight':70}})
        self.db.community_posts.insert_one({'id':self.q,'type':'qa','author_id':self.b,
            'author':{'id':self.b,'name':'Owner'},'privacy':'public','status':'published',
            'qa_info':{'question':'Synthetic?','respondent_count':999},'created_at':datetime.now(timezone.utc)})
        p=patch.object(r,'db',self.db); p.start(); self.addCleanup(p.stop)
        self.client=TestClient(self.app); self.addCleanup(self.client.close)
        self.auth={uid:{'Authorization':'Bearer '+jwt.encode({'email':uid+'@example.com',
            'exp':datetime.now(timezone.utc)+timedelta(minutes=10)},r.JWT_SECRET,algorithm=r.JWT_ALGORITHM)} for uid in [self.a,self.b]}
        self.path='/api/community/questions/'+self.q+'/answers'

    def send(self,text='answer',key=None,uid=None,**extra):
        return self.client.post(self.path,headers=dict(self.auth[uid or self.a],**{'X-Idempotency-Key':key or uuid.uuid4().hex}),json=dict(content=text,**extra))

    def read(self,uid=None,**params): return self.client.get(self.path,headers=self.auth[uid or self.a],params=params)
    def vote(self,aid,desired=True,uid=None):
        return self.client.request('PUT' if desired else 'DELETE',self.path+'/'+aid+'/helpful',headers=self.auth[uid or self.b])

    def test_auth_validation_canonical_projection_and_type(self):
        self.assertEqual(self.client.post(self.path,json={'content':'x'},headers={'X-Idempotency-Key':uuid.uuid4().hex}).status_code,401)
        for value in ['', '  ', 'x'*2001]: self.assertEqual(self.send(value).status_code,422)
        for field in ['author','is_pinned_best','verified','coach']:
            self.assertEqual(self.send(**{field:True}).status_code,422)
        receipt=self.send('  canonical  ').json(); ans=receipt['answer']
        self.assertEqual(ans['content'],'canonical'); self.assertEqual(ans['author']['id'],self.a)
        self.assertEqual(ans['author']['name'],'Canonical a'); self.assertFalse(ans['is_pinned_best'])
        self.assertFalse({'email','password','health_stats','tokens'} & set(ans['author']))
        self.assertTrue(ans['created_at'].endswith(('Z','+00:00')))
        self.db.community_posts.update_one({'id':self.q},{'$set':{'type':'photo'}})
        self.assertEqual(self.send().status_code,404); self.assertEqual(self.read().status_code,404)

    def test_durable_replay_conflict_parallel_and_count(self):
        key=uuid.uuid4().hex
        self.send(key=key)  # Real persisted receipt deliberately ignored.
        with ThreadPoolExecutor(max_workers=8) as pool:
            results=list(pool.map(lambda _:self.send(key=key),range(16)))
        self.assertTrue(all(x.status_code==200 for x in results))
        self.assertEqual(len({x.json()['answer']['id'] for x in results}),1)
        self.assertEqual(self.db.community_answers.count_documents({'question_id':self.q}),1)
        self.assertEqual(self.send('different',key=key).status_code,409)
        fresh=MongoClient('mongodb://127.0.0.1:27046'); self.addCleanup(fresh.close)
        self.assertEqual(fresh[self.name].community_answers.count_documents({'question_id':self.q}),1)
        self.assertEqual(self.client.get('/api/community/posts/'+self.q,headers=self.auth[self.a]).json()['qa_info']['respondent_count'],1)
        self.assertEqual(self.read().json()['answer_count'],1)

    def test_desired_votes_parallel_unvote_self_and_authoritative_count(self):
        aid=self.send().json()['answer']['id']
        self.assertEqual(self.vote(aid,uid=self.a).status_code,403)
        with ThreadPoolExecutor(max_workers=8) as pool:
            results=list(pool.map(lambda _:self.vote(aid),range(12)))
        self.assertTrue(all(x.status_code==200 for x in results))
        self.assertTrue(all(x.json()['upvote_count']==1 for x in results))
        self.assertEqual(self.db.community_answer_votes.count_documents({'answer_id':aid}),1)
        self.db.community_answers.update_one({'question_id':self.q},{'$set':{'upvote_count':999}})
        self.assertEqual(self.read(uid=self.b).json()['items'][0]['upvote_count'],1)
        for _ in range(3): self.assertEqual(self.vote(aid,False).json()['upvote_count'],0)
        self.assertFalse(self.client.get(self.path+'/'+aid,headers=self.auth[self.b]).json()['is_upvoted'])
        self.assertFalse(self.read().json()['items'][0]['is_pinned_best'])

    def test_stable_pagination_with_timestamp_ties_and_changing_votes(self):
        ids=[self.send(str(i)).json()['answer']['id'] for i in range(7)]
        self.db.community_answers.update_many({'question_id':self.q},{'$set':{'created_at':datetime(2026,1,1,tzinfo=timezone.utc)}})
        seen=[]; cursor=None
        while True:
            page=self.read(limit=2,**({'cursor':cursor} if cursor else {})).json()
            seen += [x['id'] for x in page['items']]; cursor=page['next_cursor']
            self.vote(ids[-1])
            if not cursor: break
        self.assertEqual(seen,sorted(ids)); self.assertEqual(len(set(seen)),7)
        self.assertEqual(self.read(cursor='bad').status_code,400)

    def test_audience_revocation_replay_read_vote_and_no_payload(self):
        key=uuid.uuid4().hex; aid=self.send(key=key).json()['answer']['id']
        for privacy in ['private','followers_only']:
            self.db.community_posts.update_one({'id':self.q},{'$set':{'privacy':privacy}})
            for response in [self.read(),self.send(key=key),self.vote(aid,uid=self.a),self.client.get(self.path+'/'+aid,headers=self.auth[self.a])]:
                self.assertEqual(response.status_code,404); self.assertEqual(set(response.json()),{'detail'})
            self.assertEqual(self.read(uid=self.b).status_code,200)
        self.db.community_follows.insert_one({'follower_id':self.a,'following_id':self.b})
        self.assertEqual(self.read().status_code,200); self.assertEqual(self.send(key=key).status_code,200)
        self.db.community_posts.update_one({'id':self.q},{'$set':{'privacy':'private'}})
        self.assertEqual(self.read().status_code,404); self.assertEqual(self.send(key=key).status_code,404)
        self.assertEqual(self.db.community_answers.count_documents({'question_id':self.q}),1)

    def test_deleted_unpublished_unknown_audience_and_identity(self):
        key=uuid.uuid4().hex; aid=self.send(key=key).json()['answer']['id']
        for field,value in [('status',None),('status','draft'),('status','unpublished'),('is_deleted',True),('privacy','unknown')]:
            self.db.community_posts.update_one({'id':self.q},{'$set':{field:value}})
            self.assertEqual(self.read().status_code,404); self.assertEqual(self.send(key=key).status_code,404)
            self.assertEqual(self.vote(aid).status_code,404)
            self.db.community_posts.update_one({'id':self.q},{'$set':{'status':'published','is_deleted':False,'privacy':'public'}})
        # Revoke the canonical identity without destroying retained fixture data.
        self.db.users.update_one({'_id':self.a},{'$set':{'email':'revoked_'+self.a+'@example.com'}})
        self.assertEqual(self.send(key=key).status_code,401); self.assertEqual(self.read().status_code,401)

    def test_question_missing_and_cross_question_answer(self):
        aid=self.send().json()['answer']['id']; self.path='/api/community/questions/missing/answers'
        self.assertEqual(self.read().status_code,404); self.assertEqual(self.send().status_code,404)
        self.assertEqual(self.vote(aid).status_code,404)

    def test_missing_unique_index_fails_closed(self):
        # New independent database, no dropping indexes or deleting any evidence.
        empty=self.mongo['saman_jcom0507_test_'+uuid.uuid4().hex]
        empty.users.insert_many(list(self.db.users.find({'_id':{'$in':[self.a,self.b]}})))
        empty.community_posts.insert_one(self.db.community_posts.find_one({'id':self.q}))
        with patch.object(r,'db',empty): self.assertEqual(self.send().status_code,503)
        self.assertEqual(empty.community_answers.count_documents({}),0)


if __name__=='__main__': unittest.main()
