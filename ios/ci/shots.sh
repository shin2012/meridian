#!/bin/bash
# 시뮬레이터에서 실제 서버에 연결해 화면을 찍는다(CI 점검용). 서버 주소·토큰은 저장소 비밀값으로만 받는다.
# 사용: SERVER=… TOKEN=… shots.sh <app 경로> <출력 폴더> [phone] [ipad]
set -u
APP="$1"; OUT="$2"; shift 2; mkdir -p "$OUT"
DEVICES="${*:-phone ipad}"
BUNDLE=kr.b-612.meridian
: "${SERVER:?MERIDIAN_SERVER 비밀값 필요}"; : "${TOKEN:?MERIDIAN_TOKEN 비밀값 필요}"
echo "::add-mask::$SERVER"; echo "::add-mask::$TOKEN"

# 찍을 사건·기사 번호(가장 최근 분석에서)
J=$(curl -s -H "Authorization: Bearer $TOKEN" "$SERVER/app/v1/digest/latest?samples=4&lang=ko")
EVENT=$(echo "$J" | python3 -c "import json,sys;d=json.load(sys.stdin);print(d['events'][0]['id'])")
ART_KO=$(echo "$J" | python3 -c "import json,sys;d=json.load(sys.stdin);print(next((a['id'] for e in d['events'] for a in e['samples'] if (a.get('language') or 'ko').startswith('ko')), d['events'][0]['samples'][0]['id']))")
ART_FX=$(echo "$J" | python3 -c "import json,sys;d=json.load(sys.stdin);print(next((a['id'] for e in d['events'] for a in e['samples'] if not (a.get('language') or 'ko').startswith('ko') and a.get('body_status')=='full'), d['events'][0]['samples'][-1]['id']))")
echo "사건 $EVENT · 기사 $ART_KO · 외국어 기사 $ART_FX"

pick() { xcrun simctl list devices available -j | python3 -c "
import json,sys,re
d=json.load(sys.stdin)['devices']
c=[(rt,x) for rt,xs in d.items() if 'iOS' in rt for x in xs if re.search(sys.argv[1], x['name'])]
c.sort(key=lambda t: t[0])
print(c[-1][1]['udid'] if c else '')" "$1"; }

wd() { local n=$1; shift; "$@" & local p=$!; ( sleep "$n"; kill -9 $p 2>/dev/null ) & local w=$!; wait $p; local r=$?; kill $w 2>/dev/null; return $r; }

shoot() {   # udid 이름 url [기다림]
  wd 30 xcrun simctl launch --terminate-running-process "$1" $BUNDLE -demoServer "$SERVER" -demoToken "$TOKEN" -open "$3" >/dev/null 2>&1
  sleep "${4:-7}"
  wd 20 xcrun simctl io "$1" screenshot --type=png "$OUT/$2.png" >/dev/null 2>&1 && echo "  찍음 $2 $(date +%T)"
  if xcrun simctl spawn "$1" launchctl list 2>/dev/null | grep -q "$BUNDLE"; then :; else echo "  ⚠️ 앱 꺼짐(CRASHED?) $2"; fi
}

run_device() {   # 기기 정규식 접두어
  local U; U=$(pick "$1")
  [ -z "$U" ] && { echo "기기 없음: $1"; return; }
  echo "== $2 ($U)"
  wd 240 xcrun simctl boot "$U" 2>/dev/null; wd 300 xcrun simctl bootstatus "$U" -b >/dev/null; echo "  부팅 $(date +%T)"
  xcrun simctl status_bar "$U" override --time "9:41" --batteryLevel 100 --cellularBars 4 2>/dev/null
  wd 120 xcrun simctl install "$U" "$APP"; echo "  설치 $(date +%T)"
  wd 60 xcrun simctl launch "$U" $BUNDLE -demoServer "$SERVER" -demoToken "$TOKEN" >/dev/null; sleep 25
  shoot "$U" "$2-01-digest" "meridian://digest" 10
  shoot "$U" "$2-02-event" "meridian://event/$EVENT" 9
  shoot "$U" "$2-03-article-ko" "meridian://article/$ART_KO" 9
  shoot "$U" "$2-04-article-foreign" "meridian://article/$ART_FX" 20
  shoot "$U" "$2-05-topics" "meridian://tab/topics" 10
  shoot "$U" "$2-06-countries" "meridian://tab/countries" 9
  shoot "$U" "$2-07-sources" "meridian://tab/sources" 9
  shoot "$U" "$2-08-bookmarks" "meridian://tab/bookmarks" 7
  shoot "$U" "$2-09-search" "meridian://search?q=%EB%AF%B8%EA%B5%AD" 9
  shoot "$U" "$2-10-settings" "meridian://settings" 6
  xcrun simctl shutdown "$U"
}

for d in $DEVICES; do
  case $d in
    phone) run_device '^iPhone 1[6-7] Pro$' phone ;;
    ipad) run_device '^iPad Pro 13' ipad ;;
  esac
done
ls "$OUT" | wc -l
