package signaling

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"math/rand/v2"
	"net"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"github.com/bedrock-tool/bedrocktool/utils/franchise/authservice"
	"github.com/coder/websocket"
	"github.com/coder/websocket/wsjson"
	"github.com/df-mc/go-nethernet"
	"github.com/google/uuid"
)

const (
	jsonRPCVersion = "2.0"

	methodSystemPing            = "System_Ping_v1_0"
	methodSystemPong            = "System_Pong_v1_0"
	methodTurnAuth              = "Signaling_TurnAuth_v1_0"
	methodSendClientMessage     = "Signaling_SendClientMessage_v1_0"
	methodReceiveMessage        = "Signaling_ReceiveMessage_v1_0"
	methodWebRTC                = "Signaling_WebRtc_v1_0"
	methodDeliveryNotification  = "Signaling_DeliveryNotification_V1_0"
	defaultJSONRPCSignalingHost = "signal.franchise.minecraft-services.net"
	jsonRPCSignalingPath        = "/ws/v1.0/messaging/connect"
	defaultJSONRPCKeepAlive     = 5 * time.Second
	jsonRPCReadLimit            = 128 << 10
)

// errIgnoredJSONRPCSignal marks a delivery receipt rather than a WebRTC signal.
// Receipts arrive through the same ReceiveMessage envelope as peer signals.
var errIgnoredJSONRPCSignal = errors.New("inner JSON-RPC message is not a WebRTC signal")

// jsonRPCDeliveryError is the service envelope sent when an outbound message
// could not be delivered to its recipient. It must not be passed to
// nethernet.Signal.UnmarshalText, which would interpret words in the human
// readable error as a signal connection ID.
type jsonRPCDeliveryError struct {
	Code    int    `json:"Code"`
	Message string `json:"Message"`
}

func (e *jsonRPCDeliveryError) Error() string {
	if e.Message == "" {
		return fmt.Sprintf("JSON-RPC signaling delivery failed (code %d)", e.Code)
	}
	return fmt.Sprintf("JSON-RPC signaling delivery failed (code %d): %s", e.Code, e.Message)
}

// JSONRPCDialer establishes the signaling connection used by Realms that
// advertise NETHERNET_JSONRPC.
type JSONRPCDialer struct {
	Service *SignalingService
	Options *websocket.DialOptions
	dial    func(context.Context, string, *websocket.DialOptions) (*websocket.Conn, *http.Response, error)

	// NetworkID is the local NetherNet ID advertised to the remote peer. A
	// random uint64 is generated when it is empty.
	NetworkID string
	// Host is the regional signaling host returned alongside the Realm address.
	// A full ws:// or wss:// URL may be used by tests and custom deployments.
	Host string
	Log  *slog.Logger

	// KeepAlive controls JSON-RPC ping frequency. Zero selects five seconds.
	KeepAlive time.Duration
}

// JSONRPCConn implements nethernet.Signaling using the newer Minecraft
// Franchise WebSocket JSON-RPC protocol.
type JSONRPCConn struct {
	conn *websocket.Conn
	d    JSONRPCDialer
	ctx  context.Context

	cancel context.CancelCauseFunc
	once   sync.Once
	closed chan struct{}

	writeMu sync.Mutex

	credentials         atomic.Pointer[nethernet.Credentials]
	credentialsReceived chan struct{}
	credentialsOnce     sync.Once
	turnAuthRequestID   string
	turnAuthArrayRetry  bool

	pending   map[string]chan jsonRPCResponse
	pendingMu sync.Mutex

	notifyCount uint32
	notifiers   map[uint32]nethernet.Notifier
	notifiersMu sync.Mutex
}

var _ nethernet.Signaling = (*JSONRPCConn)(nil)

// DialContext opens a JSON-RPC signaling connection and immediately requests
// TURN credentials. Credentials blocks until the corresponding response is
// received.
func (d JSONRPCDialer) DialContext(ctx context.Context, mcToken *authservice.MCToken) (*JSONRPCConn, error) {
	if mcToken == nil {
		return nil, fmt.Errorf("franchise/signaling: Minecraft token is nil")
	}
	if d.Options == nil {
		d.Options = &websocket.DialOptions{}
	}
	if d.Options.HTTPClient == nil {
		d.Options.HTTPClient = &http.Client{}
	}
	if d.Options.HTTPHeader == nil {
		d.Options.HTTPHeader = make(http.Header)
	} else {
		d.Options.HTTPHeader = d.Options.HTTPHeader.Clone()
	}
	if d.NetworkID == "" {
		for d.NetworkID == "" {
			if networkID := rand.Uint64(); networkID != 0 {
				d.NetworkID = strconv.FormatUint(networkID, 10)
			}
		}
	}
	if d.Log == nil {
		d.Log = slog.Default()
	}
	if d.KeepAlive <= 0 {
		d.KeepAlive = defaultJSONRPCKeepAlive
	}

	addresses, err := d.signalingURLs()
	if err != nil {
		return nil, err
	}
	d.Options.HTTPHeader.Set("Authorization", mcToken.AuthorizationHeader)
	dial := d.dial
	if dial == nil {
		dial = websocket.Dial
	}
	var (
		ws         *websocket.Conn
		dialErrors []error
	)
	for index, address := range addresses {
		// A retry is a new WebSocket handshake and must use fresh correlation
		// identifiers even though the Minecraft authorisation token is shared.
		d.Options.HTTPHeader.Set("session-id", uuid.NewString())
		d.Options.HTTPHeader.Set("request-id", uuid.NewString())
		var response *http.Response
		ws, response, err = dial(ctx, address, d.Options)
		if err == nil {
			break
		}
		if response != nil && response.Body != nil {
			_ = response.Body.Close()
		}
		dialErrors = append(dialErrors, fmt.Errorf("%s: %w", address, err))
		if ctx.Err() != nil {
			return nil, context.Cause(ctx)
		}
		// An HTTP response means that the endpoint was reached and rejected the
		// request (for example because authentication failed). Retrying another
		// host would hide that useful server response. The global fallback is
		// deliberately limited to a missing regional DNS record.
		if response != nil || !isDNSNotFound(err) {
			break
		}
		if index+1 < len(addresses) {
			d.Log.WarnContext(ctx, "regional signaling endpoint unavailable; retrying the global endpoint",
				"endpoint", address, "fallback", addresses[index+1], "error", err)
		}
	}
	if ws == nil {
		return nil, fmt.Errorf("dial JSON-RPC signaling: %w", errors.Join(dialErrors...))
	}
	// Coder/websocket defaults to 32 KiB. Full SDP offers/answers with bundled
	// ICE candidates can exceed that once wrapped in the JSON-RPC envelope.
	ws.SetReadLimit(jsonRPCReadLimit)
	signalingCtx, cancel := context.WithCancelCause(context.Background())
	c := &JSONRPCConn{
		conn:                ws,
		d:                   d,
		ctx:                 signalingCtx,
		cancel:              cancel,
		closed:              make(chan struct{}),
		credentialsReceived: make(chan struct{}),
		pending:             make(map[string]chan jsonRPCResponse),
		notifiers:           make(map[uint32]nethernet.Notifier),
	}
	if err := c.requestTurnAuth(ctx, false); err != nil {
		c.closeWithCause(err)
		return nil, fmt.Errorf("request TURN credentials: %w", err)
	}
	go c.read()
	return c, nil
}

func (d JSONRPCDialer) signalingURL() (string, error) {
	base := strings.TrimSpace(d.Host)
	if base == "" && d.Service != nil {
		base = strings.TrimSpace(d.Service.Config.ServiceURI)
	}
	if base == "" {
		base = defaultJSONRPCSignalingHost
	}
	if !strings.Contains(base, "://") {
		base = "wss://" + base
	}
	u, err := url.Parse(base)
	if err != nil {
		return "", fmt.Errorf("parse signaling host: %w", err)
	}
	switch u.Scheme {
	case "http":
		u.Scheme = "ws"
	case "https":
		u.Scheme = "wss"
	case "ws", "wss":
	default:
		return "", fmt.Errorf("unsupported signaling URL scheme %q", u.Scheme)
	}
	if u.Host == "" {
		return "", fmt.Errorf("signaling host is empty")
	}
	u.Path = jsonRPCSignalingPath
	u.RawPath = ""
	u.RawQuery = ""
	u.Fragment = ""
	return u.String(), nil
}

// signalingURLs returns the preferred signaling endpoint followed by the
// global endpoint when the preferred endpoint is a regional Minecraft host.
// Not every Realm region has a corresponding DNS record, so the global host is
// required as a compatibility fallback.
func (d JSONRPCDialer) signalingURLs() ([]string, error) {
	primary, err := d.signalingURL()
	if err != nil {
		return nil, err
	}
	u, err := url.Parse(primary)
	if err != nil {
		return nil, err
	}
	host := strings.ToLower(u.Hostname())
	const franchiseSuffix = ".franchise.minecraft-services.net"
	if !strings.HasPrefix(host, "signal-") || !strings.HasSuffix(host, franchiseSuffix) {
		return []string{primary}, nil
	}
	fallback := *u
	fallback.Host = defaultJSONRPCSignalingHost
	return []string{primary, fallback.String()}, nil
}

func isDNSNotFound(err error) bool {
	var dnsError *net.DNSError
	return errors.As(err, &dnsError) && dnsError.IsNotFound
}

// Signal sends a WebRTC signal in the nested message format required by the
// JSON-RPC signaling service.
func (c *JSONRPCConn) Signal(ctx context.Context, signal *nethernet.Signal) error {
	select {
	case <-ctx.Done():
		return context.Cause(ctx)
	case <-c.ctx.Done():
		return context.Cause(c.ctx)
	default:
	}
	if signal == nil {
		return fmt.Errorf("franchise/signaling: signal is nil")
	}

	innerParams, err := json.Marshal(struct {
		NetherNetID string `json:"netherNetId"`
		Message     string `json:"message"`
	}{NetherNetID: c.d.NetworkID, Message: signal.String()})
	if err != nil {
		return err
	}
	inner, err := json.Marshal(jsonRPCMessage{
		JSONRPC: jsonRPCVersion,
		Method:  methodWebRTC,
		Params:  innerParams,
	})
	if err != nil {
		return err
	}
	outerParams, err := json.Marshal(struct {
		ToPlayerID string `json:"toPlayerId"`
		MessageID  string `json:"messageId"`
		Message    string `json:"message"`
	}{
		ToPlayerID: signal.NetworkID,
		MessageID:  uuid.NewString(),
		Message:    string(inner),
	})
	if err != nil {
		return err
	}
	_, err = c.request(ctx, jsonRPCMessage{
		JSONRPC: jsonRPCVersion,
		ID:      jsonRPCID(uuid.NewString()),
		Method:  methodSendClientMessage,
		Params:  outerParams,
	})
	return err
}

// Notify registers a notifier for incoming signals.
func (c *JSONRPCConn) Notify(n nethernet.Notifier) func() {
	c.notifiersMu.Lock()
	i := c.notifyCount
	c.notifyCount++
	c.notifiers[i] = n
	c.notifiersMu.Unlock()
	return sync.OnceFunc(func() {
		c.notifiersMu.Lock()
		delete(c.notifiers, i)
		c.notifiersMu.Unlock()
	})
}

func (c *JSONRPCConn) Context() context.Context { return c.ctx }

// Credentials waits for the Signaling_TurnAuth_v1_0 response.
func (c *JSONRPCConn) Credentials(ctx context.Context) (*nethernet.Credentials, error) {
	if credentials := c.credentials.Load(); credentials != nil {
		return credentials, nil
	}
	select {
	case <-c.credentialsReceived:
		return c.credentials.Load(), nil
	case <-c.closed:
		return nil, context.Cause(c.ctx)
	case <-ctx.Done():
		return nil, context.Cause(ctx)
	}
}

func (c *JSONRPCConn) NetworkID() string { return c.d.NetworkID }

func (*JSONRPCConn) PongData([]byte) {}

// DisableTrickleICE reports that Realms requires all ICE candidates to be
// bundled with the initial offer.
func (*JSONRPCConn) DisableTrickleICE() bool { return true }

func (c *JSONRPCConn) Close() error { return c.closeWithCause(net.ErrClosed) }

func (c *JSONRPCConn) closeWithCause(cause error) (err error) {
	c.once.Do(func() {
		c.cancel(cause)
		c.pendingMu.Lock()
		for id, pending := range c.pending {
			pending <- jsonRPCResponse{err: cause}
			delete(c.pending, id)
		}
		c.pendingMu.Unlock()
		c.notifiersMu.Lock()
		clear(c.notifiers)
		c.notifiersMu.Unlock()
		close(c.closed)
		err = c.conn.Close(websocket.StatusNormalClosure, "")
	})
	return err
}

func (c *JSONRPCConn) read() {
	go c.keepAlive()
	for {
		var message jsonRPCMessage
		if err := wsjson.Read(c.ctx, c.conn, &message); err != nil {
			c.closeWithCause(err)
			return
		}
		if err := c.handleMessage(message); err != nil {
			c.closeWithCause(err)
			return
		}
	}
}

func (c *JSONRPCConn) keepAlive() {
	ticker := time.NewTicker(c.d.KeepAlive)
	defer ticker.Stop()
	for {
		select {
		case <-c.closed:
			return
		case <-ticker.C:
			params, _ := json.Marshal([]any{})
			if err := c.write(c.ctx, jsonRPCMessage{
				JSONRPC: jsonRPCVersion,
				ID:      jsonRPCID(uuid.NewString()),
				Method:  methodSystemPing,
				Params:  params,
			}); err != nil {
				c.closeWithCause(err)
				return
			}
		}
	}
}

func (c *JSONRPCConn) handleMessage(message jsonRPCMessage) error {
	id := jsonRPCIDString(message.ID)
	if id == c.turnAuthRequestID {
		if message.Error != nil {
			// Known signaling deployments disagree on whether this no-argument
			// method takes {} or []. Current Realms accepts {}, while some newer
			// service revisions require []; retry that form once on Invalid Params.
			if message.Error.Code == -32602 && !c.turnAuthArrayRetry {
				c.turnAuthArrayRetry = true
				return c.requestTurnAuth(c.ctx, true)
			}
			return message.Error
		}
		var credentials nethernet.Credentials
		if err := json.Unmarshal(message.Result, &credentials); err != nil {
			return fmt.Errorf("decode TURN credentials: %w", err)
		}
		c.credentials.Store(&credentials)
		c.credentialsOnce.Do(func() { close(c.credentialsReceived) })
		return nil
	}
	if id != "" && c.resolvePending(id, message) {
		return nil
	}

	switch message.Method {
	case methodReceiveMessage:
		if len(message.ID) != 0 {
			if err := c.acknowledge(message.ID); err != nil {
				return err
			}
		}
		for _, item := range jsonRPCItems(message.Params) {
			signal, err := parseJSONRPCReceiveItem(item)
			if err != nil {
				var deliveryErr *jsonRPCDeliveryError
				if errors.As(err, &deliveryErr) {
					c.d.Log.Warn("JSON-RPC signaling message delivery failed",
						slog.Int("code", deliveryErr.Code),
						slog.String("message", deliveryErr.Message),
					)
					return deliveryErr
				}
				if errors.Is(err, errIgnoredJSONRPCSignal) {
					c.d.Log.Debug("received JSON-RPC signaling delivery receipt")
					continue
				}
				c.d.Log.Warn("could not decode JSON-RPC signal", slog.Any("error", err))
				continue
			}
			c.notify(signal)
		}
	case methodSystemPong, methodDeliveryNotification:
		if len(message.ID) != 0 {
			return c.acknowledge(message.ID)
		}
	default:
		if message.Error != nil {
			c.d.Log.Warn("JSON-RPC signaling request failed", slog.Any("error", message.Error))
		}
	}
	return nil
}

func (c *JSONRPCConn) requestTurnAuth(ctx context.Context, arrayParams bool) error {
	var params json.RawMessage
	if arrayParams {
		params, _ = json.Marshal([]any{})
	} else {
		params, _ = json.Marshal(struct{}{})
	}
	c.turnAuthRequestID = uuid.NewString()
	return c.write(ctx, jsonRPCMessage{
		JSONRPC: jsonRPCVersion,
		ID:      jsonRPCID(c.turnAuthRequestID),
		Method:  methodTurnAuth,
		Params:  params,
	})
}

func (c *JSONRPCConn) acknowledge(id json.RawMessage) error {
	return c.write(c.ctx, jsonRPCMessage{
		JSONRPC: jsonRPCVersion,
		ID:      id,
		Result:  json.RawMessage("null"),
	})
}

func (c *JSONRPCConn) notify(signal *nethernet.Signal) {
	c.notifiersMu.Lock()
	notifiers := make([]nethernet.Notifier, 0, len(c.notifiers))
	for _, notifier := range c.notifiers {
		notifiers = append(notifiers, notifier)
	}
	c.notifiersMu.Unlock()
	for _, notifier := range notifiers {
		_ = notifier.NotifySignal(signal)
	}
}

func (c *JSONRPCConn) write(ctx context.Context, message jsonRPCMessage) error {
	c.writeMu.Lock()
	defer c.writeMu.Unlock()
	return wsjson.Write(ctx, c.conn, message)
}

func (c *JSONRPCConn) request(ctx context.Context, message jsonRPCMessage) (json.RawMessage, error) {
	id := jsonRPCIDString(message.ID)
	if id == "" {
		return nil, fmt.Errorf("JSON-RPC request ID is empty")
	}
	response := make(chan jsonRPCResponse, 1)
	c.pendingMu.Lock()
	if _, exists := c.pending[id]; exists {
		c.pendingMu.Unlock()
		return nil, fmt.Errorf("duplicate JSON-RPC request ID %q", id)
	}
	c.pending[id] = response
	c.pendingMu.Unlock()

	if err := c.write(ctx, message); err != nil {
		c.removePending(id)
		return nil, err
	}
	select {
	case result := <-response:
		return result.result, result.err
	case <-ctx.Done():
		c.removePending(id)
		return nil, context.Cause(ctx)
	case <-c.ctx.Done():
		c.removePending(id)
		return nil, context.Cause(c.ctx)
	}
}

func (c *JSONRPCConn) resolvePending(id string, message jsonRPCMessage) bool {
	c.pendingMu.Lock()
	pending, ok := c.pending[id]
	if ok {
		delete(c.pending, id)
	}
	c.pendingMu.Unlock()
	if !ok {
		return false
	}
	if message.Error != nil {
		pending <- jsonRPCResponse{err: message.Error}
	} else {
		pending <- jsonRPCResponse{result: message.Result}
	}
	return true
}

func (c *JSONRPCConn) removePending(id string) {
	c.pendingMu.Lock()
	delete(c.pending, id)
	c.pendingMu.Unlock()
}

type jsonRPCMessage struct {
	JSONRPC string          `json:"jsonrpc"`
	ID      json.RawMessage `json:"id,omitempty"`
	Method  string          `json:"method,omitempty"`
	Params  json.RawMessage `json:"params,omitempty"`
	Result  json.RawMessage `json:"result,omitempty"`
	Error   *jsonRPCError   `json:"error,omitempty"`
}

type jsonRPCResponse struct {
	result json.RawMessage
	err    error
}

type jsonRPCError struct {
	Code    int             `json:"code"`
	Message string          `json:"message"`
	Data    json.RawMessage `json:"data,omitempty"`
}

func (e *jsonRPCError) Error() string {
	if e.Message == "" {
		return fmt.Sprintf("JSON-RPC error %d", e.Code)
	}
	return fmt.Sprintf("JSON-RPC error %d: %s", e.Code, e.Message)
}

func jsonRPCID(id string) json.RawMessage {
	data, _ := json.Marshal(id)
	return data
}

func jsonRPCIDString(id json.RawMessage) string {
	var value string
	if err := json.Unmarshal(id, &value); err == nil {
		return value
	}
	return string(id)
}

func jsonRPCItems(params json.RawMessage) []json.RawMessage {
	trimmed := strings.TrimSpace(string(params))
	if strings.HasPrefix(trimmed, "[") {
		var items []json.RawMessage
		if json.Unmarshal(params, &items) == nil {
			return items
		}
	}
	if len(params) == 0 || trimmed == "null" {
		return nil
	}
	return []json.RawMessage{params}
}

func parseJSONRPCReceiveItem(item json.RawMessage) (*nethernet.Signal, error) {
	var fields map[string]json.RawMessage
	if err := json.Unmarshal(item, &fields); err != nil {
		return nil, err
	}
	message := jsonRPCStringField(fields, "Message", "message")
	if message == "" {
		return nil, fmt.Errorf("received signaling item has no message")
	}
	signal, innerNetworkID, err := parseJSONRPCSignal(message)
	if err != nil {
		return nil, err
	}
	networkID := jsonRPCStringField(fields, "From", "from", "fromPlayerId")
	if networkID == "" {
		networkID = innerNetworkID
	}
	if networkID == "" {
		return nil, fmt.Errorf("received signaling item has no sender")
	}
	signal.NetworkID = networkID
	return signal, nil
}

func parseJSONRPCSignal(message string) (*nethernet.Signal, string, error) {
	if strings.HasPrefix(strings.TrimSpace(message), "{") {
		var envelope struct {
			jsonRPCMessage
			Code    *int   `json:"Code"`
			Message string `json:"Message"`
		}
		if err := json.Unmarshal([]byte(message), &envelope); err != nil {
			return nil, "", fmt.Errorf("decode inner signaling message: %w", err)
		}
		// A service error is not a peer WebRtc message. Preserve it even if
		// there is no human-readable message, so negotiation can stop promptly.
		if envelope.Method == "" && envelope.Code != nil {
			return nil, "", &jsonRPCDeliveryError{Code: *envelope.Code, Message: envelope.Message}
		}
		switch envelope.Method {
		case methodDeliveryNotification:
			return nil, "", errIgnoredJSONRPCSignal
		case "", methodWebRTC:
		default:
			return nil, "", fmt.Errorf("unsupported inner signaling method %q", envelope.Method)
		}
		payload := envelope.Params
		if len(payload) == 0 {
			payload = envelope.Result
		}
		var fields map[string]json.RawMessage
		if err := json.Unmarshal(payload, &fields); err == nil {
			signalText := jsonRPCStringField(fields, "message", "Message", "innerMessage")
			if signalText != "" {
				signal := &nethernet.Signal{}
				if err := signal.UnmarshalText([]byte(signalText)); err != nil {
					return nil, "", fmt.Errorf("decode WebRTC signal payload: %w", err)
				}
				networkID := jsonRPCStringField(fields, "netherNetId", "NetherNetId", "fromNetherNetId", "fromPlayerId")
				return signal, networkID, nil
			}
		}
		// Never fall back to splitting JSON on spaces: an unrecognised object
		// may contain ordinary text, whose second word is not a connection ID.
		return nil, "", fmt.Errorf("inner signaling message has no WebRTC signal payload (method %q)", envelope.Method)
	}

	signal := &nethernet.Signal{}
	if err := signal.UnmarshalText([]byte(message)); err != nil {
		return nil, "", err
	}
	return signal, "", nil
}

func jsonRPCStringField(fields map[string]json.RawMessage, names ...string) string {
	for key, raw := range fields {
		for _, name := range names {
			if !strings.EqualFold(key, name) {
				continue
			}
			var value string
			if err := json.Unmarshal(raw, &value); err == nil {
				return value
			}
			return strings.TrimSpace(string(raw))
		}
	}
	return ""
}
