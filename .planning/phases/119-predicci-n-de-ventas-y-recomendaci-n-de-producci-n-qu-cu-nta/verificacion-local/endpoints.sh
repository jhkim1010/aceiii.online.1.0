#!/bin/bash
S=/private/tmp/claude-501/-Users-marcoskim-TrabajoProgramming-aceiii-online-1-0/d11e6370-f58b-40cd-8c98-7914952a2d69/scratchpad
B=http://localhost:5012/api/prediccion
AD="authorization: Bearer $(cat $S/tok_admin.txt)"
SU="authorization: Bearer $(cat $S/tok_super.txt)"
OUT=$S/ep_results.tsv; : > $OUT
t() { # desc expected method path token [body]
  local desc="$1" exp="$2" m="$3" p="$4" tok="$5" body="$6" xs="$7"
  local args=(-s -o $S/ep_body.txt -w '%{http_code}' -X "$m" "$B$p")
  [ -n "$tok" ] && args+=(-H "$tok")
  [ -n "$xs" ] && args+=(-H "x-store-id: $xs")
  [ -n "$body" ] && args+=(-H 'content-type: application/json' -d "$body")
  local code; code=$(curl "${args[@]}")
  local ex; ex=$(head -c 160 $S/ep_body.txt | tr '\n|' '  ')
  local ok=OK; [ "$code" = "$exp" ] || ok=DISCREPANCIA
  printf '%s|%s %s|%s|%s|%s|%s\n' "$desc" "$m" "$p" "$exp" "$code" "$ok" "$ex" >> $OUT
}
MID=$1; RUN_BT=$2; RUN_SIM=$3; PID=$4; OTHER_MODEL=$5; OTHER_RUN=$6; OTHER_PROD=$7; ORIGIN=$8
t "sin token" 401 GET /estado ""
t "estado" 200 GET /estado "$AD"
t "datos-usados" 200 GET /datos-usados "$AD"
t "analisis/modelos" 200 GET "/analisis/modelos?pageSize=10" "$AD"
t "analisis/modelos orden vendido" 200 GET "/analisis/modelos?orden=vendido&pageSize=5" "$AD"
t "talles" 200 GET "/analisis/modelos/$MID/talles" "$AD"
t "fundamento" 200 GET "/analisis/modelos/$MID/fundamento" "$AD"
t "analisis/atributos fabric" 200 GET "/analisis/atributos?dimension=fabric" "$AD"
t "analisis/atributos nivel=variante invalido" 400 GET "/analisis/atributos?dimension=variante" "$AD"
t "atributos lista" 200 GET "/atributos?pageSize=10" "$AD"
t "atributos PUT" 200 PUT "/atributos/$PID" "$AD" '{"fabric":"Algodón","fit":"Regular","priceBand":"medio"}'
t "atributos PUT priceBand invalido" 400 PUT "/atributos/$PID" "$AD" '{"priceBand":"carisimo"}'
t "atributos PUT producto ajeno" 404 PUT "/atributos/$OTHER_PROD" "$AD" '{"fabric":"X"}'
t "configuracion GET" 200 GET /configuracion "$AD"
t "configuracion PUT leadTime (admin)" 200 PUT /configuracion "$AD" '{"leadTimeDays":21}'
t "configuracion PUT enabled por admin de tienda" 403 PUT /configuracion "$AD" '{"enabled":false}'
t "configuracion PUT lead fuera de rango" 400 PUT /configuracion "$AD" '{"leadTimeDays":9999}'
t "backtest/ultimo" 200 GET /backtest/ultimo "$AD"
t "backtest puntos modelo" 200 GET "/backtest/$RUN_BT/puntos?nivel=modelo&clave=118&modelo=media_movil_8" "$AD"
t "backtest puntos nivel=variante" 400 GET "/backtest/$RUN_BT/puntos?nivel=variante&clave=118&modelo=media_movil_8" "$AD"
t "backtest puntos run ajeno" 404 GET "/backtest/$OTHER_RUN/puntos?nivel=modelo&clave=118&modelo=media_movil_8" "$AD"
t "simulacion/ultimo" 200 GET /simulacion/ultimo "$AD"
t "simulacion trazas" 200 GET "/simulacion/$RUN_SIM/trazas?modelId=$MID" "$AD"
t "simulacion traza" 200 GET "/simulacion/$RUN_SIM/traza?modelId=$MID&origin=$ORIGIN" "$AD"
t "simulacion trazas run ajeno" 404 GET "/simulacion/$OTHER_RUN/trazas?modelId=$MID" "$AD"
t "fundamento modelId ajeno" 404 GET "/analisis/modelos/$OTHER_MODEL/fundamento" "$AD"
t "talles modelId ajeno" 404 GET "/analisis/modelos/$OTHER_MODEL/talles" "$AD"
t "superadmin sin tienda" 400 GET /estado "$SU"
t "superadmin PUT configuracion sin tienda" 400 PUT /configuracion "$SU" "{\"leadTimeDays\":21}"
t "superadmin con storeId=6" 200 GET "/estado?storeId=6" "$SU"
t "admin pide storeId de otra tienda" 403 GET "/estado?storeId=9" "$AD"
t "superadmin PUT enabled (X-Store-Id: 6)" 200 PUT /configuracion "$SU" '{"enabled":true}' 6
t "ejecutar" 201 POST /ejecutar "$AD"
t "ejecutar inmediato (en_curso o iniciado)" 201 POST /ejecutar "$AD"
cat $OUT
