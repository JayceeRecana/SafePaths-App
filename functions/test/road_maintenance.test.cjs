const {test}=require('node:test'),assert=require('node:assert/strict');
const geometry=parts=>({type:'MultiLineString',segments:parts.map(points=>({points:points.map(([lng,lat])=>({lng,lat}))}))});
test('maintenance graph connects T-junctions symmetrically without connecting disjoint pieces across a gap',async()=>{
 const {roadAdjacency}=await import('../../supabase/functions/_shared/proof_roads.mjs');
 const roads=[{id:'a',geometry:geometry([[[121.001,14.676],[121.002,14.676]],[[121.008,14.676],[121.009,14.676]]])},{id:'touch',geometry:geometry([[[121.0015,14.676],[121.0015,14.677]]])},{id:'gap',geometry:geometry([[[121.005,14.675],[121.005,14.677]]])}];
 const links=roadAdjacency(roads);assert.deepEqual(links.get('a'),['touch']);assert.deepEqual(links.get('touch'),['a']);assert.deepEqual(links.get('gap'),[]);
});
test('incremental import preserves known links, removes orphan/self links and attaches only the new geometry',async()=>{
 const {roadAdjacency}=await import('../../supabase/functions/_shared/proof_roads.mjs');
 const roads=[{id:'a',neighbors:['b','deleted','a'],geometry:geometry([[[121.001,14.676],[121.002,14.676]]])},{id:'b',neighbors:['a'],geometry:null},{id:'new',geometry:geometry([[[121.0015,14.676],[121.0015,14.677]]])}];
 const links=roadAdjacency(roads,new Set(['new']));assert.deepEqual(links.get('a'),['b','new']);assert.deepEqual(links.get('new'),['a']);assert.deepEqual(links.get('b'),['a']);
});
test('dense or oversized maintenance graph fails within an explicit comparison/pixel-free geometry budget',async()=>{
 const {roadAdjacency}=await import('../../supabase/functions/_shared/proof_roads.mjs');
 const points=Array.from({length:1024},(_,i)=>[121.001+i/10000000,14.676]);
 assert.throws(()=>roadAdjacency([{id:'a',geometry:geometry([points])},{id:'b',geometry:geometry([points])}]),{code:'resource-exhausted'});
 assert.deepEqual([...roadAdjacency([])],[]);
});
