const { connect } = require('./pg-client');
const ok=[],bad=[];
const t=(n,c)=> c?ok.push(n):bad.push(n);
(async()=>{
 const c = await connect();
 const tryQ=async(sql,p)=>{try{await c.query(sql,p);return null}catch(e){return e.code}};

 // M5 — legacy 허용, 미지의 값 거부
 t('M5 source=legacy 허용', null===await tryQ("INSERT INTO sales(store_id,source) VALUES(1,'legacy')"));
 t('M5 source=pos 여전히 허용', null===await tryQ("INSERT INTO sales(store_id,source) VALUES(1,'pos')"));
 t('M5 미지의 source 거부(23514)', '23514'===await tryQ("INSERT INTO sales(store_id,source) VALUES(1,'bogus')"));

 // M1 — PENDING/DONE 규칙
 t('M1 PENDING 은 ventago_id NULL 허용', null===await tryQ(
   "INSERT INTO legacy_entity_maps(store_id,entity,legacy_id) VALUES(1,'sale','v1')"));
 t('M1 DONE 인데 target 없으면 거부', '23514'===await tryQ(
   "INSERT INTO legacy_entity_maps(store_id,entity,legacy_id,status) VALUES(1,'sale','v2','DONE')"));
 t('M1 DONE + target 허용', null===await tryQ(
   "INSERT INTO legacy_entity_maps(store_id,entity,legacy_id,ventago_id,status) VALUES(1,'sale','v3',10,'DONE')"));
 t('M1 같은 (store,entity,legacy) 중복 거부(23505)', '23505'===await tryQ(
   "INSERT INTO legacy_entity_maps(store_id,entity,legacy_id) VALUES(1,'sale','v1')"));
 t('M1 잘못된 status 거부', '23514'===await tryQ(
   "INSERT INTO legacy_entity_maps(store_id,entity,legacy_id,status) VALUES(1,'sale','v9','WIP')"));

 // M7 — 리스 획득/차단/만료후재획득
 await c.query("INSERT INTO legacy_import_leases(store_id,legacy_import_id,holder,lease_expires_at) VALUES(1,1,'w1',now()+interval '5 min')");
 let r=await c.query(`INSERT INTO legacy_import_leases(store_id,legacy_import_id,holder,lease_expires_at)
   VALUES(1,1,'w2',now()+interval '5 min')
   ON CONFLICT (store_id) DO UPDATE SET holder=EXCLUDED.holder, lease_expires_at=EXCLUDED.lease_expires_at,
     updated_at=now() WHERE legacy_import_leases.lease_expires_at < now() RETURNING holder`);
 t('M7 살아있는 리스는 재획득 차단(0행)', r.rowCount===0);
 await c.query("UPDATE legacy_import_leases SET lease_expires_at=now()-interval '1 min' WHERE store_id=1");
 r=await c.query(`INSERT INTO legacy_import_leases(store_id,legacy_import_id,holder,lease_expires_at)
   VALUES(1,1,'w2',now()+interval '5 min')
   ON CONFLICT (store_id) DO UPDATE SET holder=EXCLUDED.holder, lease_expires_at=EXCLUDED.lease_expires_at,
     updated_at=now() WHERE legacy_import_leases.lease_expires_at < now() RETURNING holder`);
 t('M7 만료된 리스는 재획득 성공(워커 사망 후 자동 해제)', r.rowCount===1 && r.rows[0].holder==='w2');

 // M2 — status 에 CHECK 가 없다는 근거 재확인
 t('M2 legacy_imports.status 에 CHECK 없음(RUNNING 삽입 가능)', null===await tryQ(
   "INSERT INTO legacy_imports(store_id,user_id,status) VALUES(1,1,'RUNNING')"));

 // 테넌트 CASCADE
 await c.query("INSERT INTO stores(name) VALUES('tmp')");
 const s2=(await c.query("SELECT id FROM stores WHERE name='tmp'")).rows[0].id;
 await c.query("INSERT INTO legacy_alerts(store_id,legacy_id,fecha,evento) VALUES($1,1,'2026-01-01','x')",[s2]);
 await c.query("DELETE FROM stores WHERE id=$1",[s2]);
 const left=(await c.query("SELECT count(*)::int n FROM legacy_alerts WHERE store_id=$1",[s2])).rows[0].n;
 t('매장 삭제 시 legacy_alerts CASCADE 정리', left===0);

 console.log('PASS:'); ok.forEach(x=>console.log('  ✔',x));
 if(bad.length){console.log('FAIL:');bad.forEach(x=>console.log('  ✘',x));}
 console.log(`\n${ok.length} passed, ${bad.length} failed`);
 await c.end(); process.exit(bad.length?1:0);
})();
