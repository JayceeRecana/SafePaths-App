// Protocol fixture only. It does not execute hosted Supabase Storage or Postgres RLS.
exports.storageFixture = function storageFixture({bucket="report-photos-proof", origin="https://aaaaaaaaaaaaaaaaaaaa.supabase.co"} = {}) {
  const files = new Map(); let publicBucket = false, writes = 0, failUploadResponse = false, missingAs400 = false;
  const secret = 'fixture-server-secret';
  const json = (body,status=200) => new Response(JSON.stringify(body),{status,headers:{'content-type':'application/json'}});
  const fetcher = async (raw, options = {}) => {
    const url=new URL(raw), path=url.pathname, method=options.method??'GET';
    if (url.origin!==origin) throw new Error('Unexpected fixture host');
    if (path.startsWith('/storage/v1/object/sign/') && method==='GET') {
      if (url.searchParams.get('token')!=='fixture-signed') return json({error:'denied'},403);
      const file=files.get(path.replace('/storage/v1/object/sign/',''));
      return file?new Response(file,{headers:{'content-type':'image/jpeg'}}):json({},404);
    }
    const headers=new Headers(options.headers);
    if (headers.get('authorization')!==`Bearer ${secret}`||headers.get('apikey')!==secret) return json({error:'denied'},403);
    if(path.startsWith('/storage/v1/object/authenticated/') && method==='GET'){const file=files.get(path.replace('/storage/v1/object/authenticated/',''));return file?new Response(file,{headers:{'content-type':'image/jpeg'}}):json({},404);}
    if (path===`/storage/v1/bucket/${bucket}`) return json({id:bucket,public:publicBucket});
    if (path.startsWith('/storage/v1/object/info/')) {
      const file=files.get(path.replace('/storage/v1/object/info/',''));
      return file?json({size:file.length,contentType:'image/jpeg'}):missingAs400?json({statusCode:'404',error:'not_found'},400):json({error:'not_found'},404);
    }
    if (path.startsWith('/storage/v1/object/sign/')&&method==='POST') return json({signedURL:`${path.replace('/storage/v1','')}?token=fixture-signed`});
    if (path.startsWith('/storage/v1/object/')&&method==='POST') {
      const key=path.replace('/storage/v1/object/','');
      if(files.has(key)) return json({error:'duplicate'},409);
      files.set(key,new Uint8Array(options.body)); writes++;
      if(failUploadResponse) {failUploadResponse=false;throw new Error('lost upload response');}
      return json({Key:key});
    }
    return json({},404);
  };
  return {files,fetcher,secret,origin,get writes(){return writes;},set publicBucket(value){publicBucket=value;},set loseUploadResponse(value){failUploadResponse=value;},set missingInfoAs400(value){missingAs400=value;}};
};
