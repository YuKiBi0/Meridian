package api

import (
	"crypto/hmac"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/hex"
	"net"
	"net/http"
	"strconv"
	"strings"
	"sync"
	"time"
)

const (
	cookieName  = "meridian_session"
	sessionTTL  = 30 * 24 * time.Hour
	loginWindow = time.Minute
	loginMax    = 5
)

// auth checks the admin token (Bearer header, for scripts) or a signed
// session cookie (for the console). The cookie holds only its expiry and
// an HMAC keyed by the token, so changing the token logs everyone out.
type auth struct {
	token  string
	key    []byte
	secure bool
	path   string
}

func newAuth(token string, secure bool, path string) *auth {
	k := sha256.Sum256([]byte("meridian-session:" + token))
	if path == "" {
		path = "/"
	}
	return &auth{token: token, key: k[:], secure: secure, path: path}
}

func (a *auth) tokenOK(t string) bool {
	return subtle.ConstantTimeCompare([]byte(t), []byte(a.token)) == 1
}

func (a *auth) sign(exp string) string {
	m := hmac.New(sha256.New, a.key)
	m.Write([]byte(exp))
	return hex.EncodeToString(m.Sum(nil))
}

// check reports whether r is authenticated and whether it used the cookie.
func (a *auth) check(r *http.Request) (ok, viaCookie bool) {
	if h := r.Header.Get("Authorization"); strings.HasPrefix(h, "Bearer ") {
		return a.tokenOK(strings.TrimPrefix(h, "Bearer ")), false
	}
	c, err := r.Cookie(cookieName)
	if err != nil {
		return false, false
	}
	exp, sig, found := strings.Cut(c.Value, ".")
	if !found || !hmac.Equal([]byte(sig), []byte(a.sign(exp))) {
		return false, false
	}
	unix, err := strconv.ParseInt(exp, 10, 64)
	if err != nil || time.Now().Unix() > unix {
		return false, false
	}
	return true, true
}

func (a *auth) setCookie(w http.ResponseWriter) {
	exp := strconv.FormatInt(time.Now().Add(sessionTTL).Unix(), 10)
	http.SetCookie(w, &http.Cookie{
		Name:     cookieName,
		Value:    exp + "." + a.sign(exp),
		Path:     a.path,
		MaxAge:   int(sessionTTL.Seconds()),
		HttpOnly: true,
		Secure:   a.secure,
		SameSite: http.SameSiteStrictMode,
	})
}

func (a *auth) clearCookie(w http.ResponseWriter) {
	http.SetCookie(w, &http.Cookie{
		Name:     cookieName,
		Path:     a.path,
		MaxAge:   -1,
		HttpOnly: true,
		Secure:   a.secure,
		SameSite: http.SameSiteStrictMode,
	})
}

// limiter counts failed logins per IP over a sliding window.
type limiter struct {
	mu   sync.Mutex
	fail map[string][]time.Time
}

func newLimiter() *limiter { return &limiter{fail: map[string][]time.Time{}} }

func (l *limiter) recent(ip string, now time.Time) []time.Time {
	kept := l.fail[ip][:0]
	for _, t := range l.fail[ip] {
		if now.Sub(t) < loginWindow {
			kept = append(kept, t)
		}
	}
	if len(kept) == 0 {
		delete(l.fail, ip)
	} else {
		l.fail[ip] = kept
	}
	return kept
}

func (l *limiter) blocked(ip string) bool {
	l.mu.Lock()
	defer l.mu.Unlock()
	return len(l.recent(ip, time.Now())) >= loginMax
}

func (l *limiter) failed(ip string) {
	l.mu.Lock()
	defer l.mu.Unlock()
	now := time.Now()
	l.fail[ip] = append(l.recent(ip, now), now)
}

// clientIP trusts X-Real-IP / X-Forwarded-For only from trusted proxies.
func clientIP(r *http.Request, trusted []*net.IPNet) string {
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		host = r.RemoteAddr
	}
	ip := net.ParseIP(host)
	for _, n := range trusted {
		if ip != nil && n.Contains(ip) {
			if v := r.Header.Get("X-Real-IP"); v != "" {
				return v
			}
			if v := r.Header.Get("X-Forwarded-For"); v != "" {
				first, _, _ := strings.Cut(v, ",")
				return strings.TrimSpace(first)
			}
		}
	}
	return host
}
