package main

import (
	"crypto/tls"
	"encoding/json"
	"log"
	"net"
	"net/http"
	"net/http/httputil"
	"net/url"
	"os"
	"strings"
	"time"
)

type accountConfig struct {
	host string
}

type routeConfig struct {
	path     string
	protocol string
}

var accounts = map[string]accountConfig{
	"vp-us": {host: "cffdg.mindfreak.online"},
	"vp-ge": {host: "fgfja.mindfreak.online"},
	"vp-uk": {host: "dbaai.mindfreak.online"},
	"vp-sg": {host: "dcafc.mindfreak.online"},
}

func loadAccounts() {
	routesEnv := strings.TrimSpace(os.Getenv("ROUTES"))
	if routesEnv == "" {
		return
	}

	for _, route := range strings.Split(routesEnv, ",") {
		parts := strings.SplitN(strings.TrimSpace(route), "=", 2)
		if len(parts) != 2 {
			continue
		}

		key := strings.Trim(strings.TrimSpace(parts[0]), "/")
		backend := strings.TrimSpace(parts[1])
		host, _, err := net.SplitHostPort(backend)
		if err != nil {
			host = backend
		}

		if key != "" && host != "" {
			accounts[key] = accountConfig{host: host}
		}
	}
}

func accountFromRequest(req *http.Request) (string, accountConfig, bool) {
	host := strings.ToLower(strings.Split(req.Host, ":")[0])
	for key, account := range accounts {
		if strings.ToLower(account.host) == host {
			return key, account, true
		}
	}

	segments := strings.Split(strings.Trim(req.URL.Path, "/"), "/")
	if len(segments) == 0 || segments[0] == "" {
		return "", accountConfig{}, false
	}

	account, ok := accounts[segments[0]]
	return segments[0], account, ok
}

func routeFromPath(accountKey string, path string) (routeConfig, bool) {
	segments := strings.Split(strings.Trim(path, "/"), "/")

	if len(segments) == 1 && segments[0] == accountKey {
		return routeConfig{path: "/ovpn", protocol: "openvpn"}, true
	}

	if len(segments) != 2 || segments[0] != accountKey {
		return routeConfig{}, false
	}

	switch segments[1] {
	case "ssh":
		return routeConfig{path: "/ssh", protocol: "ssh"}, true
	case "vless":
		return routeConfig{path: "/vless", protocol: "tls"}, true
	default:
		return routeConfig{}, false
	}
}

func clientIP(req *http.Request) string {
	forwardedFor := req.Header.Get("X-Forwarded-For")
	if forwardedFor != "" {
		return strings.TrimSpace(strings.Split(forwardedFor, ",")[0])
	}

	host, _, err := net.SplitHostPort(req.RemoteAddr)
	if err == nil {
		return host
	}

	return req.RemoteAddr
}

func writeText(w http.ResponseWriter, status int, body string) {
	w.Header().Set("Content-Type", "text/plain; charset=utf-8")
	w.WriteHeader(status)
	_, _ = w.Write([]byte(body))
}

func healthHandler(w http.ResponseWriter, req *http.Request) {
	body, _ := json.MarshalIndent(map[string]any{
		"status":        "ok",
		"uptimeSeconds": int64(time.Since(startedAt).Seconds()),
		"accounts":      len(accounts),
	}, "", "  ")

	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.Header().Set("Cache-Control", "no-store")
	_, _ = w.Write(body)
}

func homeHandler(w http.ResponseWriter, req *http.Request) {
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.Header().Set("Cache-Control", "no-cache, no-store, must-revalidate")
	_, _ = w.Write([]byte("<b><font color='red'>VIPER</font> <font color='green'>Panel</font></b>"))
}

func newProxy(account accountConfig, route routeConfig) (*httputil.ReverseProxy, error) {
	target, err := url.Parse("https://" + account.host)
	if err != nil {
		return nil, err
	}

	proxy := httputil.NewSingleHostReverseProxy(target)
	originalDirector := proxy.Director

	proxy.Director = func(req *http.Request) {
		originalDirector(req)

		req.URL.Scheme = "https"
		req.URL.Host = account.host
		req.URL.Path = route.path
		req.URL.RawPath = ""
		req.URL.RawQuery = ""

		req.Host = account.host
		req.Header.Set("Host", account.host)
		req.Header.Set("X-Target-Protocol", route.protocol)
		req.Header.Set("X-Real-IP", clientIP(req))
		if req.Header.Get("X-Forwarded-Proto") == "" {
			req.Header.Set("X-Forwarded-Proto", "https")
		}
	}

	proxy.Transport = &http.Transport{
		Proxy: http.ProxyFromEnvironment,
		DialContext: (&net.Dialer{
			Timeout:   30 * time.Second,
			KeepAlive: 30 * time.Second,
		}).DialContext,
		ForceAttemptHTTP2:     false,
		MaxIdleConns:          100,
		IdleConnTimeout:       90 * time.Second,
		TLSHandshakeTimeout:   15 * time.Second,
		ExpectContinueTimeout: 1 * time.Second,
		TLSClientConfig: &tls.Config{
			ServerName:         account.host,
			InsecureSkipVerify: true,
		},
	}

	proxy.ErrorHandler = func(w http.ResponseWriter, req *http.Request, err error) {
		log.Printf("proxy error path=%s target=%s err=%v", req.URL.Path, account.host, err)
		writeText(w, http.StatusBadGateway, "Bad Gateway")
	}

	return proxy, nil
}

var startedAt = time.Now()

func main() {
	loadAccounts()

	port := strings.TrimSpace(os.Getenv("PORT"))
	if port == "" {
		port = "8080"
	}

	mux := http.NewServeMux()

	mux.HandleFunc("/", func(w http.ResponseWriter, req *http.Request) {
		if req.URL.Path == "/health" {
			healthHandler(w, req)
			return
		}

		if req.URL.Path == "/" {
			homeHandler(w, req)
			return
		}

		accountKey, account, ok := accountFromRequest(req)
		if !ok {
			writeText(w, http.StatusNotFound, "Not Found")
			return
		}

		route, ok := routeFromPath(accountKey, req.URL.Path)
		if !ok {
			writeText(w, http.StatusNotFound, "Not Found")
			return
		}

		proxy, err := newProxy(account, route)
		if err != nil {
			log.Printf("create proxy failed: %v", err)
			writeText(w, http.StatusBadGateway, "Bad Gateway")
			return
		}

		log.Printf("%s %s -> https://%s%s protocol=%s", req.Method, req.URL.Path, account.host, route.path, route.protocol)
		proxy.ServeHTTP(w, req)
	})

	server := &http.Server{
		Addr:              ":" + port,
		Handler:           mux,
		ReadHeaderTimeout: 30 * time.Second,
		IdleTimeout:       15 * time.Minute,
	}

	log.Printf("server listening on :%s", port)
	for key, account := range accounts {
		log.Printf("route /%s -> https://%s", key, account.host)
	}

	if err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
		log.Fatalf("server failed: %v", err)
	}
}
