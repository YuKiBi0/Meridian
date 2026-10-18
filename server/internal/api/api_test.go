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

	"github.com/YuKiBi0/Meridian/server/internal/store"
	"github.com/YuKiBi0/Meridian/server/internal/stream"
	"github.com/YuKiBi0/Meridian/server/internal/timer"
)

const testToken = "test-token-0123456789"

type listener struct {
	hub *stream.Hub
	p   *store.Persister
}

func (l listener) State(s timer.State)       { l.hub.Publish(stream.Encode("state", s.Seq, s)) }
func (l listener) Reminder(f timer.Fired)    { l.hub.Publish(stream.Encode("reminder", -1, f)) }
func (l listener) Persist(p timer.Persisted) { l.p.Save(p) }

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
	e := timer.NewEngine(timer.New(), listener{hub, p})
	srv := New(Config{
		BasePath:   "/meridian",
		AdminToken: testToken,
		Console:    fstest.MapFS{"index.html": {Data: []byte("<html>console</html>")}},
	}, e, hub, st)
	ts := httptest.NewServer(srv.Handler())
	t.Cleanup(func() {
		ts.CloseClientConnections()
		ts.Close()
		e.Close()
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
	_, err = conn.Exec(ctx, `TRUNCATE presets, timer_state, op_logs`)
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
	req, _ := http.NewRequest("GET", base+"/api/v1/admin/clients", nil)
	req.Header.Set("Authorization", "Bearer "+testToken)
	resp, _ = http.DefaultClient.Do(req)
	if resp.StatusCode != 200 {
		t.Fatalf("bearer %d", resp.StatusCode)
	}
}

func TestTimerFlowAndStream(t *testing.T) {
	ts, c := newTestServer(t)
	base := ts.URL + "/meridian"
	call(t, c, "POST", base+"/api/v1/admin/login", map[string]string{"token": testToken}, nil)

	resp, err := http.Get(base + "/api/v1/stream?role=client")
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	if ct := resp.Header.Get("Content-Type"); !strings.HasPrefix(ct, "text/event-stream") {
		t.Fatalf("content type %s", ct)
	}
	events := make(chan [2]string, 16)
	go func() {
		sc := bufio.NewScanner(resp.Body)
		var name string
		for sc.Scan() {
			line := sc.Text()
			switch {
			case strings.HasPrefix(line, "event: "):
				name = strings.TrimPrefix(line, "event: ")
			case strings.HasPrefix(line, "data: "):
				events <- [2]string{name, strings.TrimPrefix(line, "data: ")}
			}
		}
	}()
	next := func() (string, map[string]any) {
		select {
		case ev := <-events:
			var m map[string]any
			json.Unmarshal([]byte(ev[1]), &m)
			return ev[0], m
		case <-time.After(3 * time.Second):
			t.Fatal("no event")
		}
		return "", nil
	}

	if name, m := next(); name != "state" || m["status"] != "idle" {
		t.Fatalf("initial %s %v", name, m)
	}

	var st timer.State
	code := call(t, c, "POST", base+"/api/v1/admin/timer/start", map[string]any{
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
	if code := call(t, c, "POST", base+"/api/v1/admin/timer/pause", map[string]any{"if_seq": stale}, nil); code != 409 {
		t.Fatalf("stale pause %d", code)
	}
	if code := call(t, c, "POST", base+"/api/v1/admin/timer/pause", nil, &st); code != 200 || st.Status != timer.Paused {
		t.Fatalf("pause %d %+v", code, st)
	}
	next()
	if code := call(t, c, "POST", base+"/api/v1/admin/timer/extend", map[string]any{"delta_ms": 60000, "mode": "total"}, &st); code != 200 {
		t.Fatalf("extend %d", code)
	}
	if st.TotalMs != 61500 {
		t.Fatalf("total after extend %d", st.TotalMs)
	}
	next()
	if code := call(t, c, "POST", base+"/api/v1/admin/timer/resume", nil, nil); code != 200 {
		t.Fatalf("resume %d", code)
	}
	next()
	if code := call(t, c, "POST", base+"/api/v1/admin/timer/end", nil, nil); code != 200 {
		t.Fatalf("end %d", code)
	}
	if name, m := next(); name != "state" || m["status"] != "idle" || m["last_end"] == nil {
		t.Fatalf("after end %s %v", name, m)
	}
	if code := call(t, c, "POST", base+"/api/v1/admin/timer/pause", nil, nil); code != 409 {
		t.Fatalf("pause idle %d", code)
	}
	var counts map[string]int
	call(t, c, "GET", base+"/api/v1/admin/clients", nil, &counts)
	if counts["client"] != 1 {
		t.Fatalf("counts %v", counts)
	}
}

func TestPresets(t *testing.T) {
	ts, c := newTestServer(t)
	base := ts.URL + "/meridian/api/v1/admin"
	call(t, c, "POST", base+"/login", map[string]string{"token": testToken}, nil)

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
	if code := call(t, c, "POST", base+"/timer/start", map[string]any{"preset_id": b.ID}, &st); code != 200 || st.TotalMs != 900000 || st.OnExpire != timer.Overtime {
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
