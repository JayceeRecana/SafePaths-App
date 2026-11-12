const {test,before}=require('node:test'),assert=require('node:assert/strict');
const {storageFixture}=require('./support/proof_storage_fixture.cjs'),{jpeg}=require('./support/media_fixture.cjs');
let Media,validate,sha256;
before(async()=>{({ProofMediaStorage:Media,validateMediaJpeg:validate}=await import('../../supabase/functions/_shared/proof_media.mjs'));({sha256}=await import('../../supabase/functions/_shared/proof_common.mjs'));});
test('media parser accepts a genuine bounded synthetic JPEG and rejects corrupt, huge and metadata-bearing input',()=>{
 assert.deepEqual(validate(jpeg(),'avatar'),{width:24,height:24});
 for(const bytes of [new Uint8Array([255,216,255,1,255,217]),jpeg().slice(0,-2),new Uint8Array([...jpeg(),0]),new Uint8Array(2*1024*1024+1)])assert.throws(()=>validate(bytes,'feedback'),{code:'invalid-argument'});
 const exif=new Uint8Array([255,216,255,225,0,8,69,120,105,102,0,0,...jpeg().slice(2)]);assert.throws(()=>validate(exif,'feedback'),{code:'invalid-argument'});
 const huge=jpeg();let index=-1;for(let i=0;i<huge.length-8;i++)if(huge[i]===255 && huge[i+1]===192){index=i;break;}assert.ok(index>0);huge[index+7]=32;huge[index+8]=0;assert.throws(()=>validate(huge,'avatar'),{code:'invalid-argument'});
});
test('private media upload/read is immutable, purpose-bound and recovers a lost Storage response',async()=>{
 const fixture=storageFixture(),avatar=new Media({url:fixture.origin,secret:fixture.secret,fetcher:fixture.fetcher},'avatar'),feedback=new Media({url:fixture.origin,secret:fixture.secret,fetcher:fixture.fetcher},'feedback'),bytes=jpeg(),hash=await sha256(bytes);
 fixture.loseUploadResponse=true;const reference=await avatar.upload('resident',hash,bytes);assert.equal(await avatar.upload('resident',hash,bytes),reference);assert.equal(fixture.writes,1);assert.deepEqual(await avatar.read(reference),bytes);
 await assert.rejects(()=>avatar.validate(reference,'other'),{code:'permission-denied'});assert.throws(()=>feedback.parse(reference),{code:'invalid-argument'});await assert.rejects(()=>avatar.signed(reference),{code:'permission-denied'});
 const other=await feedback.upload('resident',hash,bytes);assert.notEqual(reference,other);assert.equal(fixture.writes,2);
});
test('stored media corruption and accidentally public buckets fail instead of becoming a false upload success',async()=>{
 const fixture=storageFixture(),store=new Media({url:fixture.origin,secret:fixture.secret,fetcher:fixture.fetcher},'avatar'),bytes=jpeg(),hash=await sha256(bytes),reference=await store.upload('resident',hash,bytes);
 const damaged=jpeg();damaged[damaged.length-5]^=1;fixture.files.set(`report-photos-proof/avatars/resident/${hash}.jpg`,damaged);await assert.rejects(()=>store.read(reference),{code:'media-unavailable'});
 fixture.publicBucket=true;await assert.rejects(()=>store.upload('resident',hash,bytes),{code:'unavailable'});
 fixture.publicBucket=false;fixture.files.set(`report-photos-proof/avatars/resident/${hash}.jpg`,bytes);
 const denied=new Media({url:fixture.origin,secret:fixture.secret,fetcher:async(url,options)=>url.includes('/object/authenticated/')?new Response(JSON.stringify({statusCode:'403',error:'denied'}),{status:400}):fixture.fetcher(url,options)},'avatar');
 await assert.rejects(()=>denied.read(reference),{code:'unavailable'});
});
