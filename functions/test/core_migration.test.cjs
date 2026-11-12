const {test,before}=require('node:test'),assert=require('node:assert/strict');
let weather,risk,verify;
before(async()=>{weather=await import('../../supabase/functions/_shared/proof_weather.mjs');risk=await import('../../supabase/functions/_shared/risk_domain.mjs');verify=(await import('../../supabase/functions/_shared/proof_push.mjs')).verifyWorkerTicket;});
const now=Date.parse('2026-10-25T03:00:00Z');
function forecast(){return {current_units:{time:'unixtime',interval:'seconds',precipitation:'mm',wind_speed_10m:'m/s',temperature_2m:'°C',relative_humidity_2m:'%'},current:{time:now/1000,interval:900,precipitation:1,wind_speed_10m:3,temperature_2m:29,relative_humidity_2m:75,weather_code:61},hourly_units:{time:'unixtime',temperature_2m:'°C',precipitation_probability:'%'},hourly:{time:[now/1000],temperature_2m:[28],precipitation_probability:[70],weather_code:[63]}};}
test('weather converts interval precipitation to mm/hour and retains provider observation time',()=>{
 const parsed=weather.parseWeather(forecast(),now);assert.equal(parsed.precipitationIntensity,4);assert.equal(parsed.windSpeed,3);assert.equal(+parsed.observedAt,now);assert.equal(parsed.forecast.length,1);assert.equal(parsed.currentState,'moderateRain');assert.ok(weather.usableWeather(parsed,now));
});
test('weather rejects invalid units, stale/future model data and incomplete numeric fields',()=>{
 for(const mutate of [b=>b.current_units.wind_speed_10m='km/h',b=>b.current.time-=1801,b=>b.current.time+=61,b=>b.current.interval=0,b=>b.current.precipitation=NaN,b=>b.current.relative_humidity_2m=101]){
  const b=forecast();mutate(b);assert.throws(()=>weather.parseWeather(b,now));
 }
 const parsed=weather.parseWeather(forecast(),now);
 assert.equal(weather.usableWeather({...parsed,studyArea:'marulas'},now),false);
 assert.equal(weather.usableWeather({...parsed,available:false},now),false);
 assert.equal(weather.usableWeather({...parsed,isOverrideMode:true,overrideExpiresAt:new Date(now)},now),false);
});
test('forecast gaps stay gaps rather than manufacturing hourly predictions',()=>{
 const b=forecast();delete b.hourly;assert.deepEqual(weather.parseWeather(b,now).forecast,[]);
});
test('portable risk and confidence match existing formula across weather, age, neighbors and caution states',()=>{
 const original=require('../domain.cjs');
 for(const state of weather.weatherStates)for(const age of [0,31,61,121,1450]) {
  const roads=[{id:'a',status:'passable',vulnerability:'high',neighbors:['b'],riskScore:60,communityCondition:'outdated',updatedAt:new Date(now-age*60000),geometry:{segments:[{points:[{lat:14.67,lon:121},{lat:14.68,lon:121}]}]}},{id:'b',status:'not_passable',riskScore:100,warningStartTime:new Date(now-age*60000),neighbors:['a']}];
  const reports=[{id:'r',roadId:'a',userId:'u',status:'under_review',severity:'High',authorityScore:80,observedAt:new Date(now-age*60000),location:{lat:14.67,lng:121}},{id:'s',roadId:'a',userId:'v',status:'pending',severity:'Low',observedAt:new Date(now-60000)}];
  assert.deepEqual(risk.calculateRisks(roads,reports,state,now),original.calculateRisks(roads,reports,state,now));
  assert.equal(risk.confidence(reports[0],roads,reports,state,now),original.confidence(reports[0],roads,reports,state,now));
 }
});
test('core worker tickets are purpose-bound and cannot be copied from the push queue',async()=>{
 const secret='K'.repeat(43),time=String(now/1000),nonce='a'.repeat(32);
 const make=purpose=>new Headers({'x-proof-worker-time':time,'x-proof-worker-nonce':nonce,'x-proof-worker-signature':require('node:crypto').createHmac('sha256',secret).update(`${time}.${nonce}${purpose?'.'+purpose:''}`).digest('hex')});
 assert.equal(await verify(make(''),secret,()=>now,'core-maintenance'),null);
 assert.equal(await verify(make('core-maintenance'),secret,()=>now),null);
 assert.equal(await verify(make('core-maintenance'),secret,()=>now,'core-maintenance'),nonce);
});
module.exports={forecast};

test('test bootstrap defaults to dry-run, refuses main credentials and selects test-area geometry',()=>{
 const {options,inArea}=require('../tools/prepare-core-migration.cjs');
 assert.throws(()=>options(['--project=safepaths-92c3d','--credentials=x']));
 assert.equal(options(['--project=safepaths-test','--credentials=x']).apply,false);
 assert.equal(inArea({geometry:{segments:[{points:[{lon:121.009,lat:14.676},{lon:121.010,lat:14.676}]}]}}),true);
 assert.equal(inArea({geometry:{segments:[{points:[{lon:120.984,lat:14.675},{lon:120.984,lat:14.677}]}]}}),false);
});
