package api

import (
	"bufio"
	"context"
	"encoding/json"
	"net/http"
	"net/http/cookiejar"
	"net/http/httptest"
	"os"
	"strings"
	"testing"
	"testing/fstest"
	"time"

	"github.com/jackc/pgx/v5"

	"github.com/YuKiBi0/Meridian/server/internal/rooms"
	"github.com/YuKiBi0/Meridian/server/internal/store"
	"github.com/YuKiBi0/Meridian/server/internal/stream"
	"github.com/YuKiBi0/Meridian/server/internal/timer"
)

const testToken = "test-token-0123456789"

// newTestServer needs MERIDIAN_TEST_DATABASE_URL pointing at a disposable
// database; its tables are truncated.
func newTestServer(t *testing.T) (*httptest.Server, *http.Client) {
	url := os.Getenv("MERIDIAN_TEST_DATABASE_URL")
	if url == "" {
		t.Skip("MERIDIAN_TEST_DATABASE_URL not set")
	}
	ctx := context.Background()
	st, err := store.Open(ctx, url)
	if err != nil {
		t.Fatal(err)
	}
	if err := truncate(ctx, url); err != nil {
		t.Fatal(err)
	}
	hub := stream.NewHub()
	p := store.NewPersister(st)
	rm, err := rooms.Load(ctx, st, hub, p)
	if err != nil {
		t.Fatal(err)
	}
	srv := New(Config{
		BasePath:   "/meridian",
		AdminToken: testToken,
		Console:    fstest.MapFS{"index.html": {Data: []byte("<html>console</html>")}},
	}, rm, hub, st)
	ts := httptest.NewServer(srv.Handler())
	t.Cleanup(func() {
		ts.CloseClientConnections()
		ts.Close()
		rm.Close()
		p.Close(ctx)
		st.Close()
	})
	jar, _ := cookiejar.New(nil)
	return ts, &http.Client{Jar: jar, Timeout: 5 * time.Second}
}

func truncate(ctx context.Context, url string) error {
	conn, err := pgx.Connect(ctx, url)
	if err != nil {
		return err
	}
	defer conn.Close(ctx)
	_, err = conn.Exec(ctx, `TRUNCATE presets, rooms, op_logs CASCADE`)
	return err
}

func call(t *testing.T, c *http.Client, method, url string, body any, out any) int {
	t.Helper()
	var r *strings.Reader
	if body != nil {
		b, _ := json.Marshal(body)
		r = strings.NewReader(string(b))
	} else {
		r = strings.NewReader("")
	}
	req, _ := http.NewRequest(method, url, r)
	req.Header.Set("Content-Type", "application/json")
	resp, err := c.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	if out != nil {
		json.NewDecoder(resp.Body).Decode(out)
	}
	return resp.StatusCode
}

// newRoom logs in and creates a room, returning the admin API base and the
// room's id.
func newRoom(t *testing.T, ts *httptest.Server, c *http.Client, name string) (string, string) {
	t.Helper()
	base := ts.URL + "/meridian/api/v1"
	call(t, c, "POST", base+"/admin/login", map[string]string{"token": testToken}, nil)
	var room struct{ ID string }
	if code := call(t, c, "POST", base+"/admin/rooms", map[string]string{"name": name}, &room); code != 201 {
		t.Fatalf("create room %d", code)
	}
	return base, room.ID
}

// events subscribes to url and returns a function yielding the next event.
func events(t *testing.T, url string) func() (string, map[string]any) {
	t.Helper()
	resp, err := http.Get(url)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { resp.Body.Close() })
	if ct := resp.Header.Get("Content-Type"); !strings.HasPrefix(ct, "text/event-stream") {
		t.Fatalf("content type %s", ct)
	}
	ch := make(chan [2]string, 16)
	go func() {
		defer close(ch)
		sc := bufio.NewScanner(resp.Body)
		var name string
		for sc.Scan() {
			line := sc.Text()
			switch {
			case strings.HasPrefix(line, "event: "):
				name = strings.TrimPrefix(line, "event: ")
			case strings.HasPrefix(line, "data: "):
				ch <- [2]string{name, strings.TrimPrefix(line, "data: ")}
			}
		}
	}()
	return func() (string, map[string]any) {
		t.Helper()
		select {
		case ev, ok := <-ch:
			if !ok {
				return "", nil // stream closed
			}
			var m map[string]any
			json.Unmarshal([]byte(ev[1]), &m)
			return ev[0], m
		case <-time.After(3 * time.Second):
			t.Fatal("no event")
		}
		return "", nil
	}
}

func TestRoutingAndAuth(t *testing.T) {
	ts, c := newTestServer(t)
	base := ts.URL + "/meridian"

	noRedirect := &http.Client{CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }}
	resp, _ := noRedirect.Get(ts.URL + "/meridian")
	if resp.StatusCode != http.StatusMovedPermanently || resp.Header.Get("Location") != "/meridian/" {
		t.Fatalf("redirect: %d %s", resp.StatusCode, resp.Header.Get("Location"))
	}
	if code := call(t, c, "GET", base+"/healthz", nil, nil); code != 200 {
		t.Fatalf("healthz %d", code)
	}
	if code := call(t, c, "GET", base+"/api/v1/admin/presets", nil, nil); code != 401 {
		t.Fatalf("unauthenticated %d", code)
	}
	if code := call(t, c, "POST", base+"/api/v1/admin/login", map[string]string{"token": "nope"}, nil); code != 401 {
		t.Fatalf("bad login %d", code)
	}
	if code := call(t, c, "POST", base+"/api/v1/admin/login", map[string]string{"token": testToken}, nil); code != 204 {
		t.Fatalf("login %d", code)
	}
	if code := call(t, c, "GET", base+"/api/v1/admin/session", nil, nil); code != 204 {
		t.Fatalf("session %d", code)
	}
	resp, _ = c.Get(base + "/some/route")
	if resp.StatusCode != 200 {
		t.Fatalf("spa fallback %d", resp.StatusCode)
	}
	if code := call(t, c, "GET", base+"/api/v1/nope", nil, nil); code != 404 {
		t.Fatalf("unknown api %d", code)
	}

	// Bearer works for scripts.
	req, _ := http.NewRequest("GET", base+"/api/v1/admin/rooms", nil)
	req.Header.Set("Authorization", "Bearer "+testToken)
	resp, _ = http.DefaultClient.Do(req)
	if resp.StatusCode != 200 {
		t.Fatalf("bearer %d", resp.StatusCode)
	}
}

func TestTimerFlowAndStream(t *testing.T) {
	ts, c := newTestServer(t)
	api, room := newRoom(t, ts, c, "一号厅")
	base := api + "/admin/rooms/" + room

	next := events(t, api+"/stream?role=client&r="+room)
	if name, m := next(); name != "room" || m["id"] != room || m["name"] != "一号厅" {
		t.Fatalf("room event %s %v", name, m)
	}
	if name, m := next(); name != "state" || m["status"] != "idle" {
		t.Fatalf("initial %s %v", name, m)
	}

	var st timer.State
	code := call(t, c, "POST", base+"/timer/start", map[string]any{
		"total_ms": 1500, "title": "测试",
		"reminders": []map[string]any{{"at_ms": 1000, "text": "快到了"}},
	}, &st)
	if code != 200 || st.Status != timer.Running {
		t.Fatalf("start %d %+v", code, st)
	}
	if name, m := next(); name != "state" || m["status"] != "running" {
		t.Fatalf("after start %s %v", name, m)
	}
	if name, m := next(); name != "reminder" || m["text"] != "快到了" {
		t.Fatalf("reminder %s %v", name, m)
	}

	stale := st.Seq - 1
	if code := call(t, c, "POST", base+"/timer/pause", map[string]any{"if_seq": stale}, nil); code != 409 {
		t.Fatalf("stale pause %d", code)
	}
	if code := call(t, c, "POST", base+"/timer/pause", nil, &st); code != 200 || st.Status != timer.Paused {
		t.Fatalf("pause %d %+v", code, st)
	}
	next()
	if code := call(t, c, "POST", base+"/timer/extend", map[string]any{"delta_ms": 60000, "mode": "total"}, &st); code != 200 {
		t.Fatalf("extend %d", code)
	}
	if st.TotalMs != 61500 {
		t.Fatalf("total after extend %d", st.TotalMs)
	}
	next()
	if code := call(t, c, "POST", base+"/timer/reduce", map[string]any{"delta_ms": 30000, "mode": "total"}, &st); code != 200 {
		t.Fatalf("reduce %d", code)
	}
	if st.TotalMs != 31500 || st.Status != timer.Paused {
		t.Fatalf("after reduce %+v", st)
	}
	next()
	if code := call(t, c, "PUT", base+"/timer/reminders", map[string]any{
		"reminders": []map[string]any{{"at_ms": 10000, "text": "十秒"}, {"at_ms": 40000, "text": "太晚"}},
	}, nil); code != 400 {
		t.Fatalf("reminder past total %d", code)
	}
	if code := call(t, c, "PUT", base+"/timer/reminders", map[string]any{
		"reminders": []map[string]any{{"at_ms": 10000, "text": "十秒"}},
	}, &st); code != 200 || len(st.Reminders) != 1 || st.Reminders[0].Fired || st.Reminders[0].DurationMs != 8000 {
		t.Fatalf("set reminders %d %+v", code, st.Reminders)
	}
	if name, m := next(); name != "state" || len(m["reminders"].([]any)) != 1 {
		t.Fatalf("after reminders %s %v", name, m)
	}
	staleRem := st.RemindersSeq - 1
	var e struct{ Error struct{ Code string } }
	if code := call(t, c, "PUT", base+"/timer/reminders", map[string]any{
		"reminders": []map[string]any{}, "if_reminders_seq": staleRem,
	}, &e); code != 409 || e.Error.Code != "reminders_conflict" {
		t.Fatalf("stale reminders %d %+v", code, e)
	}
	if code := call(t, c, "POST", base+"/timer/resume", nil, nil); code != 200 {
		t.Fatalf("resume %d", code)
	}
	next()
	if code := call(t, c, "POST", base+"/timer/end", nil, nil); code != 200 {
		t.Fatalf("end %d", code)
	}
	if name, m := next(); name != "state" || m["status"] != "idle" || m["last_end"] == nil {
		t.Fatalf("after end %s %v", name, m)
	}
	if code := call(t, c, "POST", base+"/timer/pause", nil, nil); code != 409 {
		t.Fatalf("pause idle %d", code)
	}
	var sum struct{ Clients int }
	call(t, c, "GET", base, nil, &sum)
	if sum.Clients != 1 {
		t.Fatalf("clients %d", sum.Clients)
	}
}

// openStream subscribes as role and returns the names of events received
// within wait.
func openStream(t *testing.T, url string) func(wait time.Duration) []string {
	resp, err := http.Get(url)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { resp.Body.Close() })
	names := make(chan string, 16)
	go func() {
		sc := bufio.NewScanner(resp.Body)
		for sc.Scan() {
			if line := sc.Text(); strings.HasPrefix(line, "event: ") {
				names <- strings.TrimPrefix(line, "event: ")
			}
		}
	}()
	return func(wait time.Duration) []string {
		var got []string
		deadline := time.After(wait)
		for {
			select {
			case n := <-names:
				got = append(got, n)
			case <-deadline:
				return got
			}
		}
	}
}

func TestPresetsEventReachesConsolesOnly(t *testing.T) {
	ts, c := newTestServer(t)
	base, room := newRoom(t, ts, c, "一号厅")
	console := openStream(t, base+"/stream?role=console&r="+room)
	lobby := openStream(t, base+"/stream?role=console")
	client := openStream(t, base+"/stream?role=client&r="+room)
	console(300 * time.Millisecond)
	lobby(300 * time.Millisecond)
	client(300 * time.Millisecond)
	call(t, c, "POST", base+"/admin/presets", map[string]any{"name": "开场", "total_ms": 300000}, nil)
	if got := console(500 * time.Millisecond); len(got) != 1 || got[0] != "presets" {
		t.Fatalf("console events %v", got)
	}
	if got := lobby(200 * time.Millisecond); len(got) != 1 || got[0] != "presets" {
		t.Fatalf("lobby events %v", got)
	}
	if got := client(200 * time.Millisecond); len(got) != 0 {
		t.Fatalf("client events %v", got)
	}
}

func TestPresets(t *testing.T) {
	ts, c := newTestServer(t)
	api, room := newRoom(t, ts, c, "一号厅")
	base := api + "/admin"

	var a, b store.Preset
	if code := call(t, c, "POST", base+"/presets", map[string]any{"name": "开场", "total_ms": 300000}, &a); code != 201 {
		t.Fatalf("create %d", code)
	}
	call(t, c, "POST", base+"/presets", map[string]any{"name": "路演", "total_ms": 900000, "on_expire": "overtime",
		"reminders": []map[string]any{{"at_ms": 300000, "text": "还剩 5 分钟"}}}, &b)
	if code := call(t, c, "POST", base+"/presets", map[string]any{"name": "", "total_ms": 1000}, nil); code != 400 {
		t.Fatalf("invalid create %d", code)
	}
	if code := call(t, c, "PUT", base+"/presets/order", map[string]any{"ids": []string{b.ID, a.ID}}, nil); code != 204 {
		t.Fatalf("reorder %d", code)
	}
	var list []store.Preset
	call(t, c, "GET", base+"/presets", nil, &list)
	if len(list) != 2 || list[0].ID != b.ID || len(list[0].Reminders) != 1 {
		t.Fatalf("list %+v", list)
	}
	a.Name = "开场白"
	if code := call(t, c, "PUT", base+"/presets/"+a.ID, a, nil); code != 200 {
		t.Fatalf("update %d", code)
	}
	var st timer.State
	if code := call(t, c, "POST", base+"/rooms/"+room+"/timer/start", map[string]any{"preset_id": b.ID}, &st); code != 200 || st.TotalMs != 900000 || st.OnExpire != timer.Overtime {
		t.Fatalf("start preset %d %+v", code, st)
	}
	if code := call(t, c, "DELETE", base+"/presets/"+a.ID, nil, nil); code != 204 {
		t.Fatalf("delete %d", code)
	}
	if code := call(t, c, "DELETE", base+"/presets/"+a.ID, nil, nil); code != 404 {
		t.Fatalf("delete again %d", code)
	}
	time.Sleep(200 * time.Millisecond) // op logs are written asynchronously
	var logs []store.LogEntry
	call(t, c, "GET", base+"/logs", nil, &logs)
	if len(logs) < 5 {
		t.Fatalf("logs %d", len(logs))
	}
}

func TestRooms(t *testing.T) {
	ts, c := newTestServer(t)
	base, a := newRoom(t, ts, c, "路演厅")
	admin := base + "/admin/rooms"

	// Names may repeat; ids are UUIDv7.
	var b struct{ ID, Name string }
	if code := call(t, c, "POST", admin, map[string]string{"name": " 路演厅 "}, &b); code != 201 || b.Name != "路演厅" || b.ID == a {
		t.Fatalf("duplicate name %d %+v", code, b)
	}
	if b.ID[14] != '7' {
		t.Fatalf("not a v7 uuid %s", b.ID)
	}
	if code := call(t, c, "POST", admin, map[string]string{"name": "  "}, nil); code != 400 {
		t.Fatalf("empty name %d", code)
	}

	// Clients must name an existing room.
	for q, want := range map[string]int{"": 400, "?r=nope": 404, "?r=" + rooms.NewID(): 404} {
		resp, _ := http.Get(base + "/stream" + q)
		resp.Body.Close()
		if resp.StatusCode != want {
			t.Fatalf("stream%s %d, want %d", q, resp.StatusCode, want)
		}
	}
	var pub map[string]string
	if code := call(t, c, "GET", base+"/rooms/"+strings.ToUpper(a), nil, &pub); code != 200 || pub["name"] != "路演厅" || pub["id"] != a {
		t.Fatalf("public room %d %v", code, pub)
	}
	if code := call(t, c, "GET", base+"/rooms/"+rooms.NewID(), nil, nil); code != 404 {
		t.Fatalf("public missing room %d", code)
	}

	// Rooms count down independently.
	inA := events(t, base+"/stream?role=client&r="+a)
	inB := events(t, base+"/stream?role=client&r="+b.ID)
	lobby := openStream(t, base+"/stream?role=console")
	inA()
	inA()
	inB()
	inB()
	lobby(200 * time.Millisecond)
	call(t, c, "POST", admin+"/"+a+"/timer/start", map[string]any{"total_ms": 60000, "title": "第一场"}, nil)
	if name, m := inA(); name != "state" || m["status"] != "running" || m["title"] != "第一场" {
		t.Fatalf("room a %s %v", name, m)
	}
	if got := lobby(300 * time.Millisecond); len(got) != 1 || got[0] != "rooms" {
		t.Fatalf("lobby after start %v", got)
	}
	var list []struct {
		ID      string
		Name    string
		Clients int
		State   timer.State
	}
	call(t, c, "GET", admin, nil, &list)
	if len(list) != 2 || list[0].ID != a || list[0].State.Status != timer.Running || list[1].State.Status != timer.Idle || list[1].Clients != 1 {
		t.Fatalf("list %+v", list)
	}

	// Renaming tells everyone in the room; the countdown title is separate.
	if code := call(t, c, "PUT", admin+"/"+b.ID, map[string]string{"name": "问答厅"}, nil); code != 200 {
		t.Fatalf("rename %d", code)
	}
	if name, m := inB(); name != "room" || m["name"] != "问答厅" {
		t.Fatalf("rename event %s %v", name, m)
	}

	// Deleting disconnects the room with room_deleted and nothing else.
	if code := call(t, c, "DELETE", admin+"/"+a, nil, nil); code != 204 {
		t.Fatalf("delete %d", code)
	}
	if name, m := inA(); name != "room_deleted" || m["id"] != a {
		t.Fatalf("delete event %s %v", name, m)
	}
	if name, _ := inA(); name != "" {
		t.Fatalf("stream still open: %s", name)
	}
	if code := call(t, c, "POST", admin+"/"+a+"/timer/pause", nil, nil); code != 404 {
		t.Fatalf("op on deleted room %d", code)
	}
	if code := call(t, c, "DELETE", admin+"/"+a, nil, nil); code != 404 {
		t.Fatalf("delete again %d", code)
	}
	resp, _ := http.Get(base + "/stream?r=" + a)
	resp.Body.Close()
	if resp.StatusCode != 404 {
		t.Fatalf("stream of deleted room %d", resp.StatusCode)
	}
	call(t, c, "GET", admin, nil, &list)
	if len(list) != 1 || list[0].Name != "问答厅" {
		t.Fatalf("list after delete %+v", list)
	}
}

func TestRoomsSurviveRestart(t *testing.T) {
	ts, c := newTestServer(t)
	base, room := newRoom(t, ts, c, "常驻")
	call(t, c, "POST", base+"/admin/rooms/"+room+"/timer/start", map[string]any{"total_ms": 600000, "title": "长跑"}, nil)
	call(t, c, "POST", base+"/admin/rooms/"+room+"/timer/pause", nil, nil)

	ctx := context.Background()
	st, err := store.Open(ctx, os.Getenv("MERIDIAN_TEST_DATABASE_URL"))
	if err != nil {
		t.Fatal(err)
	}
	defer st.Close()
	// Writes are asynchronous; wait for the paused state to land.
	deadline := time.Now().Add(3 * time.Second)
	for {
		rs, err := st.ListRooms(ctx)
		if err != nil {
			t.Fatal(err)
		}
		if len(rs) == 1 && rs[0].Timer != nil && rs[0].Timer.Status == timer.Paused {
			break
		}
		if time.Now().After(deadline) {
			t.Fatalf("not persisted: %+v", rs)
		}
		time.Sleep(50 * time.Millisecond)
	}
	p := store.NewPersister(st)
	defer p.Close(ctx)
	rm, err := rooms.Load(ctx, st, stream.NewHub(), p)
	if err != nil {
		t.Fatal(err)
	}
	defer rm.Close()
	info, e, ok := rm.Get(room)
	if !ok || info.Name != "常驻" {
		t.Fatalf("room not restored %+v", info)
	}
	if s := e.Snapshot(); s.Status != timer.Paused || s.Title != "长跑" || s.RemainingMs <= 0 {
		t.Fatalf("timer not restored %+v", s)
	}
}
