#!/usr/bin/env bash
# Race tests for join_room and swipe_and_match.
# Session A takes the room lock and holds it for 4 seconds.
# Session B starts while A still holds it, so both run "at the same time".
# Usage: bash supabase/tests/race_test.sh [room code]   (needs DATABASE_URL)

DB="${DATABASE_URL:?set DATABASE_URL first}"
CODE="${1:-9999}"
FAIL=0

q() { psql "$DB" -X -q -t -A -c "$1" 2>&1; }

check() {
  if [ "$2" = "$3" ]; then echo "  PASS  $1"
  else echo "  FAIL  $1 (expected $3, got $2)"; FAIL=1; fi
}

ROOM=$(q "select id from rooms where code = '$CODE'")
[ -n "$ROOM" ] || { echo "Room $CODE not found"; exit 1; }

echo "Test 1: two people join the same room at once"
q "update rooms set guest_id = null, status = 'waiting' where id = '$ROOM'" > /dev/null
q "begin; select join_room('$CODE', 'user-b'); select pg_sleep(4); commit;" > /dev/null &
sleep 2
OUT=$(q "select join_room('$CODE', 'user-c')")
wait
check "the second person gets no slot" "$OUT" ""
check "the first person keeps the slot" "$(q "select guest_id from rooms where id = '$ROOM'")" "user-b"

echo "Test 2: both users like the same movie at once"
q "update rooms set guest_id = 'user-b', status = 'active' where id = '$ROOM'; delete from swipes where room_id = '$ROOM'; delete from matches where room_id = '$ROOM';" > /dev/null
q "begin; select swipe_and_match('$ROOM', 'user-a', 550, 'movie', 'like'); select pg_sleep(4); commit;" > /dev/null &
sleep 2
OUT=$(q "select swipe_and_match('$ROOM', 'user-b', 550, 'movie', 'like')")
wait
check "the second like sees the first and matches" "$OUT" "t"
check "exactly one match is created" "$(q "select count(*) from matches where room_id = '$ROOM'")" "1"

echo "Test 3: a repeated swipe is ignored"
check "the repeat returns false" "$(q "select swipe_and_match('$ROOM', 'user-b', 550, 'movie', 'like')")" "f"
check "still one swipe row per user" "$(q "select count(*) from swipes where room_id = '$ROOM' and user_id = 'user-b'")" "1"

[ $FAIL -eq 0 ] && echo "All tests passed" || echo "Some tests failed"
exit $FAIL
