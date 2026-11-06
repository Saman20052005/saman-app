"""JCOM0506 real standalone MongoDB contract/concurrency tests; no mock persistence."""
import os
import uuid
import unittest
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone, timedelta
from unittest.mock import patch

os.environ['MONGO_URI'] = 'mongodb://127.0.0.1:27046'
os.environ['DB_NAME'] = 'saman_jcom0506_test_import'
from bson import ObjectId
from pymongo import MongoClient
from fastapi import FastAPI
from fastapi.testclient import TestClient
import jwt
from backend.routers import community as r
from backend.scripts.setup_community_comment_indexes import setup_indexes, validate_target


class CommentsMongoTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.uri = 'mongodb://127.0.0.1:27046'
        cls.name = 'saman_jcom0506_test_' + uuid.uuid4().hex
        validate_target(cls.uri, cls.name)
        cls.mongo = MongoClient(cls.uri, serverSelectionTimeoutMS=2000)
        cls.mongo.admin.command('ping')  # Fail, do not silently skip required real DB evidence.
        cls.db = cls.mongo[cls.name]
        setup_indexes(cls.db)
        cls.app = FastAPI()
        cls.app.include_router(r.router)

    @classmethod
    def tearDownClass(cls):
        # Keep isolated synthetic data as persistence evidence; never delete a shared database.
        cls.mongo.close()

    def setUp(self):
        self.pid = 'p_' + uuid.uuid4().hex
        self.uid = 'u_' + uuid.uuid4().hex
        self.other = 'owner_' + uuid.uuid4().hex
        self.db.users.insert_one({'_id': self.uid, 'email': self.uid+'@example.test', 'name': 'Canonical Athlete',
                                  'hashed_password': 'synthetic-private', 'health_stats': {'weight': 70}})
        self.db.community_posts.insert_one({'id': self.pid, 'author_id': self.other,
             'author': {'id': self.other, 'name': 'Post owner'}, 'privacy': 'public',
             'status': 'published', 'created_at': datetime.now(timezone.utc), 'comment_count': 999})
        self.patch = patch.object(r, 'db', self.db)
        self.patch.start()
        self.addCleanup(self.patch.stop)
        self.client = TestClient(self.app)
        self.addCleanup(self.client.close)
        # Real auth dependency validates signed synthetic token and resolves canonical user from DB.
        token = jwt.encode({'email': self.uid+'@example.test', 'exp': datetime.now(timezone.utc)+timedelta(minutes=5)},
                           r.JWT_SECRET, algorithm=r.JWT_ALGORITHM)
        self.auth = {'Authorization': 'Bearer '+token}

    def send(self, content='hello', key=None, parent=None, pid=None, **extra):
        headers = dict(self.auth, **{'X-Idempotency-Key': key or uuid.uuid4().hex})
        return self.client.post('/api/community/posts/'+(pid or self.pid)+'/comments', headers=headers,
            json=dict(content=content, parent_comment_id=parent, **extra))

    def test_auth_canonical_author_and_validation(self):
        path = '/api/community/posts/'+self.pid+'/comments'
        self.assertEqual(self.client.post(path, json={'content':'x'}, headers={'X-Idempotency-Key':uuid.uuid4().hex}).status_code,401)
        for text in ['', '   ', 'x'*2001]:
            self.assertEqual(self.send(text).status_code,422)
        self.assertEqual(self.send(author={'id':'forged','is_verified':True}).status_code,422)
        result=self.send('  canonical  ')
        self.assertEqual(result.status_code,200)
        comment=result.json()['comment']
        self.assertEqual(comment['author']['id'],self.uid)
        self.assertEqual(comment['author']['name'],'Canonical Athlete')
        self.assertFalse(comment['author']['is_verified'])
        self.assertNotIn('email',comment['author'])
        self.assertNotIn('hashed_password',comment['author'])
        self.assertNotIn('health_stats',comment['author'])
        self.assertEqual(comment['content'],'canonical')
        self.assertTrue(comment['created_at'].endswith(('Z', '+00:00')))

    def test_reply_parent_and_depth(self):
        root=self.send().json()['comment']['id']
        reply=self.send('reply',parent=root)
        self.assertEqual(reply.status_code,200)
        self.assertEqual(reply.json()['comment']['parent_comment_id'],root)
        self.assertEqual(self.send(parent=reply.json()['comment']['id']).status_code,422)
        self.assertEqual(self.send(parent=str(ObjectId())).status_code,404)
        self.assertEqual(self.send(parent='invalid').status_code,404)
        self.assertEqual(self.send(parent='').status_code,422)
        self.db.community_comments.update_one({'_id':ObjectId(root)},{'$set':{'post_id':'other-post'}})
        self.assertEqual(self.send(parent=root).status_code,404)

    def test_replay_conflict_concurrent_and_lost_response(self):
        key=uuid.uuid4().hex
        # Ignore first successful response, simulating response loss after persistence.
        self.assertEqual(self.send(key=key).status_code,200)
        with ThreadPoolExecutor(max_workers=8) as pool:
            results=list(pool.map(lambda _: self.send(key=key),range(16)))
        self.assertTrue(all(x.status_code==200 for x in results))
        self.assertEqual(len({x.json()['comment']['id'] for x in results}),1)
        self.assertEqual(self.db.community_comments.count_documents({'post_id':self.pid}),1)
        self.assertEqual(self.send('different',key=key).status_code,409)
        self.assertEqual(self.send(key=key,parent='changed-parent').status_code,409)
        self.assertEqual(self.send(key=key,parent=results[0].json()['comment']['id']).status_code,409)
        fresh=uuid.uuid4().hex
        with ThreadPoolExecutor(max_workers=8) as pool:
            races=list(pool.map(lambda _: self.send('fresh race',key=fresh),range(16)))
        self.assertEqual({x.status_code for x in races},{200})
        self.assertEqual(len({x.json()['comment']['id'] for x in races}),1)
        self.assertEqual(self.db.community_comments.count_documents({'post_id':self.pid}),2)

    def test_audience_revocation_replay_no_leak(self):
        key=uuid.uuid4().hex
        self.assertEqual(self.send(key=key).status_code,200)
        path='/api/community/posts/'+self.pid+'/comments'
        for fields in [{'privacy':'private'},{'privacy':'followers_only'},{'is_deleted':True},{'status':'unpublished'}]:
            self.db.community_posts.update_one({'id':self.pid},{'$set':dict(privacy='public',is_deleted=False,status='published',**{})})
            self.db.community_posts.update_one({'id':self.pid},{'$set':fields})
            self.assertEqual(self.client.get(path,headers=self.auth).status_code,404)
            self.assertEqual(self.send(key=key).status_code,404)
            self.assertEqual(self.send('fresh').status_code,404)
        self.db.community_posts.update_one({'id':self.pid},{'$set':{'status':'published','is_deleted':False,'privacy':'followers_only'}})
        self.db.community_follows.insert_one({'follower_id':self.uid,'following_id':self.other})
        self.assertEqual(self.send(key=key).status_code,200)
        self.db.community_follows.delete_one({'follower_id':self.uid,'following_id':self.other})
        self.assertEqual(self.send(key=key).status_code,404)
        self.assertEqual(self.client.get(path,headers=self.auth).status_code,404)

    def test_count_pagination_equal_timestamps_and_reload(self):
        roots=[self.send(str(i)).json()['comment']['id'] for i in range(5)]
        self.send('reply',parent=roots[0])
        self.db.community_comments.update_many({'post_id':self.pid},{'$set':{'created_at':datetime(2026,1,1,tzinfo=timezone.utc)}})
        ids=[]; cursor=None
        while True:
            response=self.client.get('/api/community/posts/'+self.pid+'/comments',params={'limit':2,**({'cursor':cursor} if cursor else {})})
            self.assertEqual(response.status_code,200)
            page=response.json(); ids += [c['id'] for c in page['items']]
            self.assertEqual(page['comment_count'],6)
            cursor=page['next_cursor']
            if not cursor: break
        self.assertEqual(len(ids),6); self.assertEqual(len(set(ids)),6)
        self.assertEqual(ids,sorted(ids))
        self.assertEqual(self.client.get('/api/community/posts/'+self.pid,headers=self.auth).json()['comment_count'],6)
        feed=self.client.get('/api/community/feed',headers=self.auth).json()['items']
        self.assertEqual(next(p for p in feed if p['id']==self.pid)['comment_count'],6)
        with MongoClient(self.uri) as new_connection:
            self.assertEqual(new_connection[self.name].community_comments.count_documents({'post_id':self.pid}),6)
        self.assertEqual(self.client.get('/api/community/posts/'+self.pid+'/comments',params={'cursor':'broken'}).status_code,400)

    def test_distinct_concurrent_operations_authoritative_count(self):
        with ThreadPoolExecutor(max_workers=8) as pool:
            results = list(pool.map(lambda i: self.send(str(i)), range(20)))
        self.assertEqual({r.status_code for r in results}, {200})
        self.assertEqual(len({r.json()['comment']['id'] for r in results}), 20)
        self.assertEqual(self.db.community_comments.count_documents({'post_id':self.pid}), 20)
        self.assertEqual(self.client.get('/api/community/posts/'+self.pid).json()['comment_count'], 20)
        self.assertEqual(self.db.community_posts.find_one({'id':self.pid})['comment_count'], 999)

    def test_owner_private_and_deleted_identity_fail_closed(self):
        self.db.community_posts.update_one({'id':self.pid},{'$set':{'privacy':'private','author_id':self.uid}})
        key=uuid.uuid4().hex
        self.assertEqual(self.send('x'*2000,key=key).status_code,200)
        for fields in [{'status':'draft'},{'privacy':'unknown'}]:
            self.db.community_posts.update_one({'id':self.pid},{'$set':fields})
            self.assertEqual(self.send('x'*2000,key=key).status_code,404)
            self.assertEqual(self.client.get('/api/community/posts/'+self.pid+'/comments',headers=self.auth).status_code,404)
        self.db.community_posts.update_one({'id':self.pid},{'$set':{'privacy':'public','status':'published'}})
        self.db.users.delete_one({'_id':self.uid})
        self.assertEqual(self.send().status_code,401)
        self.assertEqual(self.client.get('/api/community/posts/'+self.pid+'/comments',headers=self.auth).status_code,401)

    def test_unique_index_required_and_scope_guard(self):
        for uri,name in [('mongodb://localhost:27017','saman_jcom0506_test_no'),(self.uri,'production')]:
            with self.assertRaises(ValueError): validate_target(uri,name)
        # Separate empty collection with no guarantee cannot accept a write.
        with patch.object(r,'get_community_comments_collection',return_value=self.db['unindexed_'+uuid.uuid4().hex]):
            self.assertEqual(self.send().status_code,503)


if __name__=='__main__': unittest.main()
