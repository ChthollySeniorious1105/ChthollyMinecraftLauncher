package signaling

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/bedrock-tool/bedrocktool/utils/franchise/authservice"
	"github.com/coder/websocket"
	"github.com/coder/websocket/wsjson"
	"github.com/df-mc/go-nethernet"
	"github.com/google/uuid"
)

type notifierFunc func(*nethernet.Signal) bool

func (f notifierFunc) NotifySignal(signal *nethernet.Signal) bool { return f(signal) }

func TestJSONRPCSignalingExchange(t *testing.T) {
	t.Parallel()

	const (
		localNetworkID  = "123456789"
		remoteNetworkID = "bfad0322-9335-4845-ab6c-0dafe56ee3a2"
	)
	largeAnswer := strings.Repeat("a", 40<<10)
	serverMessages := make(chan jsonRPCMessage, 2)
	serverErrors := make(chan error, 1)
	turnRequestSeen := make(chan struct{})
	allowTurnResult := make(chan struct{})
	allowSignalResult := make(chan struct{})
	keepServerOpen := make(chan struct{})

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		report := func(err error) {
			select {
			case serverErrors <- err:
			default:
			}
		}
		if r.URL.Path != jsonRPCSignalingPath {
			report(fmt.Errorf("path = %q", r.URL.Path))
			return
		}
		if r.Header.Get("Authorization") != "MCToken test" {
			report(fmt.Errorf("Authorization = %q", r.Header.Get("Authorization")))
			return
		}
		if _, err := uuid.Parse(r.Header.Get("session-id")); err != nil {
			report(fmt.Errorf("invalid session-id: %w", err))
			return
		}
		if _, err := uuid.Parse(r.Header.Get("request-id")); err != nil {
			report(fmt.Errorf("invalid request-id: %w", err))
			return
		}

		ws, err := websocket.Accept(w, r, nil)
		if err != nil {
			report(err)
			return
		}
		defer ws.CloseNow()
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()

		var turnRequest jsonRPCMessage
		if err := wsjson.Read(ctx, ws, &turnRequest); err != nil {
			report(err)
			return
		}
		if turnRequest.Method != methodTurnAuth {
			report(fmt.Errorf("first method = %q", turnRequest.Method))
			return
		}
		if strings.TrimSpace(string(turnRequest.Params)) != "{}" {
			report(fmt.Errorf("TURN params = %s", turnRequest.Params))
			return
		}
		close(turnRequestSeen)
		select {
		case <-allowTurnResult:
		case <-ctx.Done():
			report(ctx.Err())
			return
		}
		credentials := nethernet.Credentials{
			ExpirationInSeconds: 3600,
			ICEServers: []nethernet.ICEServer{{
				Username: "user",
				Password: "pass",
				URLs:     []string{"turn:relay.example:3478"},
			}},
		}
		result, _ := json.Marshal(credentials)
		if err := wsjson.Write(ctx, ws, jsonRPCMessage{
			JSONRPC: jsonRPCVersion,
			ID:      turnRequest.ID,
			Result:  result,
		}); err != nil {
			report(err)
			return
		}

		var outgoing jsonRPCMessage
		if err := wsjson.Read(ctx, ws, &outgoing); err != nil {
			report(err)
			return
		}
		serverMessages <- outgoing
		select {
		case <-allowSignalResult:
		case <-ctx.Done():
			report(ctx.Err())
			return
		}
		if err := wsjson.Write(ctx, ws, jsonRPCMessage{
			JSONRPC: jsonRPCVersion,
			ID:      outgoing.ID,
			Result:  json.RawMessage("null"),
		}); err != nil {
			report(err)
			return
		}

		innerParams, _ := json.Marshal(map[string]any{
			"netherNetId": "987654321",
			"message":     "CONNECTRESPONSE 42 " + largeAnswer,
		})
		inner, _ := json.Marshal(jsonRPCMessage{
			JSONRPC: jsonRPCVersion,
			Method:  methodWebRTC,
			Params:  innerParams,
		})
		receipt, _ := json.Marshal(jsonRPCMessage{
			JSONRPC: jsonRPCVersion,
			Method:  methodDeliveryNotification,
			Params:  json.RawMessage(`{"messageId":"00000000-0000-0000-0000-000000000002"}`),
		})
		receiveParams, _ := json.Marshal([]any{
			map[string]any{"From": remoteNetworkID, "Message": string(receipt), "Id": uuid.NewString()},
			map[string]any{"From": remoteNetworkID, "Message": string(inner), "Id": uuid.NewString()},
		})
		if err := wsjson.Write(ctx, ws, jsonRPCMessage{
			JSONRPC: jsonRPCVersion,
			ID:      json.RawMessage("17"),
			Method:  methodReceiveMessage,
			Params:  receiveParams,
		}); err != nil {
			report(err)
			return
		}

		var ack jsonRPCMessage
		if err := wsjson.Read(ctx, ws, &ack); err != nil {
			report(err)
			return
		}
		serverMessages <- ack

		var failedRequest jsonRPCMessage
		if err := wsjson.Read(ctx, ws, &failedRequest); err != nil {
			report(err)
			return
		}
		if err := wsjson.Write(ctx, ws, jsonRPCMessage{
			JSONRPC: jsonRPCVersion,
			ID:      failedRequest.ID,
			Error:   &jsonRPCError{Code: -32000, Message: "remote player unavailable"},
		}); err != nil {
			report(err)
			return
		}
		select {
		case <-keepServerOpen:
		case <-ctx.Done():
		}
	}))
	defer server.Close()

	conn, err := (JSONRPCDialer{
		Host:      server.URL,
		NetworkID: localNetworkID,
		KeepAlive: time.Hour,
	}).DialContext(context.Background(), &authservice.MCToken{AuthorizationHeader: "MCToken test"})
	if err != nil {
		t.Fatal(err)
	}
	defer conn.Close()
	if !conn.DisableTrickleICE() {
		t.Fatal("JSON-RPC signaling must disable trickle ICE")
	}
	if conn.NetworkID() != localNetworkID {
		t.Fatalf("local network ID = %q", conn.NetworkID())
	}

	select {
	case <-turnRequestSeen:
	case err := <-serverErrors:
		t.Fatal(err)
	case <-time.After(5 * time.Second):
		t.Fatal("TURN request was not received")
	}
	credentialsCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	credentialsResult := make(chan *nethernet.Credentials, 1)
	credentialsError := make(chan error, 1)
	go func() {
		credentials, err := conn.Credentials(credentialsCtx)
		credentialsResult <- credentials
		credentialsError <- err
	}()
	select {
	case <-credentialsResult:
		t.Fatal("Credentials returned before the TURN response")
	case <-time.After(20 * time.Millisecond):
	}
	close(allowTurnResult)
	var credentials *nethernet.Credentials
	select {
	case credentials = <-credentialsResult:
		if err := <-credentialsError; err != nil {
			t.Fatal(err)
		}
	case <-time.After(5 * time.Second):
		t.Fatal("Credentials did not return after the TURN response")
	}
	if len(credentials.ICEServers) != 1 || credentials.ICEServers[0].Username != "user" {
		t.Fatalf("unexpected credentials: %#v", credentials)
	}

	incoming := make(chan *nethernet.Signal, 1)
	stop := conn.Notify(notifierFunc(func(signal *nethernet.Signal) bool {
		incoming <- signal
		return true
	}))
	defer stop()
	outgoingSignal := &nethernet.Signal{
		Type:         nethernet.SignalTypeOffer,
		ConnectionID: 42,
		Data:         "offer-sdp",
		NetworkID:    remoteNetworkID,
	}
	signalResult := make(chan error, 1)
	go func() { signalResult <- conn.Signal(context.Background(), outgoingSignal) }()
	outgoing := receiveServerMessage(t, serverMessages, serverErrors)
	if outgoing.Method != methodSendClientMessage {
		t.Fatalf("outgoing method = %q", outgoing.Method)
	}
	var outerParams struct {
		ToPlayerID string `json:"toPlayerId"`
		Message    string `json:"message"`
	}
	if err := json.Unmarshal(outgoing.Params, &outerParams); err != nil {
		t.Fatal(err)
	}
	if outerParams.ToPlayerID != remoteNetworkID {
		t.Fatalf("toPlayerId = %q", outerParams.ToPlayerID)
	}
	var inner jsonRPCMessage
	if err := json.Unmarshal([]byte(outerParams.Message), &inner); err != nil {
		t.Fatal(err)
	}
	var params struct {
		NetherNetID string `json:"netherNetId"`
		Message     string `json:"message"`
	}
	if err := json.Unmarshal(inner.Params, &params); err != nil {
		t.Fatal(err)
	}
	if params.NetherNetID != localNetworkID || params.Message != outgoingSignal.String() {
		t.Fatalf("unexpected inner params: %#v", params)
	}
	select {
	case err := <-signalResult:
		t.Fatalf("Signal returned before its JSON-RPC result: %v", err)
	case <-time.After(20 * time.Millisecond):
	}
	close(allowSignalResult)
	select {
	case err := <-signalResult:
		if err != nil {
			t.Fatal(err)
		}
	case <-time.After(5 * time.Second):
		t.Fatal("Signal did not return after its JSON-RPC result")
	}

	select {
	case signal := <-incoming:
		if signal.NetworkID != remoteNetworkID || signal.Type != nethernet.SignalTypeAnswer || signal.ConnectionID != 42 || signal.Data != largeAnswer {
			t.Fatalf("unexpected incoming signal: %#v", signal)
		}
	case err := <-serverErrors:
		t.Fatal(err)
	case <-time.After(5 * time.Second):
		t.Fatal("timed out waiting for incoming signal")
	}

	ack := receiveServerMessage(t, serverMessages, serverErrors)
	if string(ack.ID) != "17" || strings.TrimSpace(string(ack.Result)) != "null" {
		t.Fatalf("unexpected acknowledgement: %#v", ack)
	}

	err = conn.Signal(context.Background(), &nethernet.Signal{
		Type:         nethernet.SignalTypeOffer,
		ConnectionID: 43,
		Data:         "offer-sdp",
		NetworkID:    remoteNetworkID,
	})
	if err == nil || !strings.Contains(err.Error(), "remote player unavailable") {
		t.Fatalf("unexpected Signal error: %v", err)
	}
	select {
	case <-conn.Context().Done():
		t.Fatalf("single request error canceled signaling: %v", context.Cause(conn.Context()))
	default:
	}
	close(keepServerOpen)
}

func receiveServerMessage(t *testing.T, messages <-chan jsonRPCMessage, errs <-chan error) jsonRPCMessage {
	t.Helper()
	select {
	case message := <-messages:
		return message
	case err := <-errs:
		t.Fatal(err)
	case <-time.After(5 * time.Second):
		t.Fatal("timed out waiting for signaling server")
	}
	return jsonRPCMessage{}
}

func TestJSONRPCSignalingURL(t *testing.T) {
	got, err := (JSONRPCDialer{Host: "signal-westus.franchise.minecraft-services.net"}).signalingURL()
	if err != nil {
		t.Fatal(err)
	}
	want := "wss://signal-westus.franchise.minecraft-services.net" + jsonRPCSignalingPath
	if got != want {
		t.Fatalf("got %q, want %q", got, want)
	}
}

func TestJSONRPCRegionalEndpointFallsBackToGlobal(t *testing.T) {
	t.Parallel()

	serverErrors := make(chan error, 1)
	turnRequestSeen := make(chan struct{})
	keepServerOpen := make(chan struct{})
	serverDone := make(chan struct{})
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		defer close(serverDone)
		report := func(err error) {
			select {
			case serverErrors <- err:
			default:
			}
		}
		if r.URL.Path != jsonRPCSignalingPath {
			report(fmt.Errorf("path = %q", r.URL.Path))
			return
		}
		if r.Header.Get("Authorization") != "MCToken fallback-test" {
			report(fmt.Errorf("Authorization = %q", r.Header.Get("Authorization")))
			return
		}
		if _, err := uuid.Parse(r.Header.Get("session-id")); err != nil {
			report(fmt.Errorf("invalid session-id: %w", err))
			return
		}
		if _, err := uuid.Parse(r.Header.Get("request-id")); err != nil {
			report(fmt.Errorf("invalid request-id: %w", err))
			return
		}
		ws, err := websocket.Accept(w, r, nil)
		if err != nil {
			report(err)
			return
		}
		defer ws.CloseNow()
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		var request jsonRPCMessage
		if err := wsjson.Read(ctx, ws, &request); err != nil {
			report(err)
			return
		}
		if request.Method != methodTurnAuth {
			report(fmt.Errorf("first method = %q", request.Method))
			return
		}
		close(turnRequestSeen)
		select {
		case <-keepServerOpen:
		case <-ctx.Done():
			report(ctx.Err())
		}
	}))
	defer server.Close()

	const regionalHost = "signal-japaneast.franchise.minecraft-services.net"
	regionalURL := "wss://" + regionalHost + jsonRPCSignalingPath
	globalURL := "wss://" + defaultJSONRPCSignalingHost + jsonRPCSignalingPath
	var (
		attempts      []string
		authorization []string
		sessionIDs    []string
		requestIDs    []string
	)
	conn, err := (JSONRPCDialer{
		Host:      regionalHost,
		KeepAlive: time.Hour,
		dial: func(ctx context.Context, address string, options *websocket.DialOptions) (*websocket.Conn, *http.Response, error) {
			attempts = append(attempts, address)
			authorization = append(authorization, options.HTTPHeader.Get("Authorization"))
			sessionIDs = append(sessionIDs, options.HTTPHeader.Get("session-id"))
			requestIDs = append(requestIDs, options.HTTPHeader.Get("request-id"))
			if address == regionalURL {
				return nil, nil, &net.DNSError{Err: "no such host", Name: regionalHost, IsNotFound: true}
			}
			if address != globalURL {
				return nil, nil, fmt.Errorf("unexpected fallback address %q", address)
			}
			return websocket.Dial(ctx, server.URL+jsonRPCSignalingPath, options)
		},
	}).DialContext(context.Background(), &authservice.MCToken{AuthorizationHeader: "MCToken fallback-test"})
	if err != nil {
		t.Fatal(err)
	}
	if len(attempts) != 2 || attempts[0] != regionalURL || attempts[1] != globalURL {
		t.Fatalf("dial attempts = %q", attempts)
	}
	for index := range attempts {
		if authorization[index] != "MCToken fallback-test" {
			t.Fatalf("attempt %d Authorization = %q", index, authorization[index])
		}
		if _, err := uuid.Parse(sessionIDs[index]); err != nil {
			t.Fatalf("attempt %d session-id = %q: %v", index, sessionIDs[index], err)
		}
		if _, err := uuid.Parse(requestIDs[index]); err != nil {
			t.Fatalf("attempt %d request-id = %q: %v", index, requestIDs[index], err)
		}
	}
	if sessionIDs[0] == sessionIDs[1] || requestIDs[0] == requestIDs[1] {
		t.Fatal("fallback WebSocket handshake reused a correlation ID")
	}
	select {
	case <-turnRequestSeen:
	case err := <-serverErrors:
		t.Fatal(err)
	case <-time.After(5 * time.Second):
		t.Fatal("TURN request was not received through the fallback endpoint")
	}
	close(keepServerOpen)
	select {
	case <-serverDone:
	case <-time.After(5 * time.Second):
		t.Fatal("fallback signaling server did not stop")
	}
	_ = conn.Close()
	select {
	case err := <-serverErrors:
		t.Fatal(err)
	default:
	}
}

func TestJSONRPCRegionalEndpointDoesNotFallbackAfterHTTPResponse(t *testing.T) {
	t.Parallel()

	const regionalHost = "signal-japaneast.franchise.minecraft-services.net"
	attempts := 0
	_, err := (JSONRPCDialer{
		Host: regionalHost,
		dial: func(context.Context, string, *websocket.DialOptions) (*websocket.Conn, *http.Response, error) {
			attempts++
			return nil, &http.Response{StatusCode: http.StatusUnauthorized, Body: http.NoBody}, fmt.Errorf("unexpected HTTP status %d", http.StatusUnauthorized)
		},
	}).DialContext(context.Background(), &authservice.MCToken{AuthorizationHeader: "MCToken rejected"})
	if err == nil {
		t.Fatal("expected the HTTP handshake error")
	}
	if attempts != 1 {
		t.Fatalf("dial attempts = %d, want 1", attempts)
	}
}

func TestJSONRPCTurnAuthRetriesArrayParams(t *testing.T) {
	t.Parallel()

	serverErrors := make(chan error, 1)
	keepOpen := make(chan struct{})
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		ws, err := websocket.Accept(w, r, nil)
		if err != nil {
			serverErrors <- err
			return
		}
		defer ws.CloseNow()
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()

		var first jsonRPCMessage
		if err := wsjson.Read(ctx, ws, &first); err != nil {
			serverErrors <- err
			return
		}
		if strings.TrimSpace(string(first.Params)) != "{}" {
			serverErrors <- fmt.Errorf("first TURN params = %s", first.Params)
			return
		}
		if err := wsjson.Write(ctx, ws, jsonRPCMessage{
			JSONRPC: jsonRPCVersion,
			ID:      first.ID,
			Error:   &jsonRPCError{Code: -32602, Message: "Invalid params"},
		}); err != nil {
			serverErrors <- err
			return
		}

		var retry jsonRPCMessage
		if err := wsjson.Read(ctx, ws, &retry); err != nil {
			serverErrors <- err
			return
		}
		if strings.TrimSpace(string(retry.Params)) != "[]" {
			serverErrors <- fmt.Errorf("retry TURN params = %s", retry.Params)
			return
		}
		result, _ := json.Marshal(nethernet.Credentials{ExpirationInSeconds: 60})
		if err := wsjson.Write(ctx, ws, jsonRPCMessage{
			JSONRPC: jsonRPCVersion,
			ID:      retry.ID,
			Result:  result,
		}); err != nil {
			serverErrors <- err
			return
		}
		select {
		case <-keepOpen:
		case <-ctx.Done():
		}
	}))
	defer server.Close()

	conn, err := (JSONRPCDialer{Host: server.URL, KeepAlive: time.Hour}).DialContext(
		context.Background(),
		&authservice.MCToken{AuthorizationHeader: "MCToken test"},
	)
	if err != nil {
		t.Fatal(err)
	}
	defer conn.Close()
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	credentials, err := conn.Credentials(ctx)
	if err != nil {
		t.Fatal(err)
	}
	if credentials.ExpirationInSeconds != 60 {
		t.Fatalf("unexpected credentials: %#v", credentials)
	}
	select {
	case err := <-serverErrors:
		t.Fatal(err)
	default:
	}
	close(keepOpen)
}

func TestParseJSONRPCDeliveryFailure(t *testing.T) {
	item := json.RawMessage(`{
		"From":"00000000-0000-0000-0000-000000000001",
		"Message":"{\"Code\":1,\"Message\":\"Unable to deliver message to the target\"}"
	}`)

	_, err := parseJSONRPCReceiveItem(item)
	var deliveryErr *jsonRPCDeliveryError
	if !errors.As(err, &deliveryErr) {
		t.Fatalf("error = %v, want a JSON-RPC delivery error", err)
	}
	if deliveryErr.Code != 1 || deliveryErr.Message != "Unable to deliver message to the target" {
		t.Fatalf("delivery error = %#v", deliveryErr)
	}
}

func TestParseJSONRPCIgnoresNonWebRTCInnerMessage(t *testing.T) {
	inner, err := json.Marshal(jsonRPCMessage{
		JSONRPC: jsonRPCVersion,
		Method:  methodDeliveryNotification,
		Params:  json.RawMessage(`{"messageId":"00000000-0000-0000-0000-000000000002"}`),
	})
	if err != nil {
		t.Fatal(err)
	}
	item, err := json.Marshal(map[string]string{
		"From":    "00000000-0000-0000-0000-000000000001",
		"Message": string(inner),
	})
	if err != nil {
		t.Fatal(err)
	}

	_, err = parseJSONRPCReceiveItem(item)
	if !errors.Is(err, errIgnoredJSONRPCSignal) {
		t.Fatalf("error = %v, want ignored non-WebRTC message", err)
	}
}

func TestParseJSONRPCSignalMessageKinds(t *testing.T) {
	for _, test := range []struct {
		name    string
		message string
		wantErr string
	}{
		{
			name:    "unknown method remains visible",
			message: `{"method":"Signaling_Unknown_v1_0","params":{"message":"Unable to deliver"}}`,
			wantErr: "unsupported inner signaling method",
		},
		{
			name:    "unknown JSON stays out of text decoder",
			message: `{"type":"ANSWER","sdp":"Unable to deliver"}`,
			wantErr: "no WebRTC signal payload",
		},
		{
			name:    "malformed WebRTC remains visible",
			message: `{"method":"Signaling_WebRtc_v1_0","params":{"message":"CONNECTRESPONSE to invalid"}}`,
			wantErr: "decode WebRTC signal payload",
		},
	} {
		t.Run(test.name, func(t *testing.T) {
			_, _, err := parseJSONRPCSignal(test.message)
			if err == nil || !strings.Contains(err.Error(), test.wantErr) || errors.Is(err, errIgnoredJSONRPCSignal) {
				t.Fatalf("error = %v, want visible error containing %q", err, test.wantErr)
			}
		})
	}

	t.Run("service error without text", func(t *testing.T) {
		_, _, err := parseJSONRPCSignal(`{"Code":2}`)
		var deliveryErr *jsonRPCDeliveryError
		if !errors.As(err, &deliveryErr) || deliveryErr.Code != 2 {
			t.Fatalf("error = %v, want delivery error 2", err)
		}
	})
	t.Run("legacy text", func(t *testing.T) {
		signal, _, err := parseJSONRPCSignal("CONNECTRESPONSE 18446744073709551615 answer with spaces")
		if err != nil {
			t.Fatal(err)
		}
		if signal.Type != nethernet.SignalTypeAnswer || signal.ConnectionID != ^uint64(0) || signal.Data != "answer with spaces" {
			t.Fatalf("unexpected signal: %#v", signal)
		}
	})
}

func TestJSONRPCDeliveryFailureUnblocksNegotiation(t *testing.T) {
	for _, serviceAccepted := range []bool{false, true} {
		t.Run(fmt.Sprintf("serviceAccepted=%t", serviceAccepted), func(t *testing.T) {
			t.Parallel()
			ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
			defer cancel()
			serverMessages := make(chan jsonRPCMessage, 1)
			serverErrors := make(chan error, 1)
			const failureText = "Unable to deliver message to the target"
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				ws, err := websocket.Accept(w, r, nil)
				if err != nil {
					serverErrors <- err
					return
				}
				defer ws.CloseNow()
				var turnRequest jsonRPCMessage
				if err := wsjson.Read(ctx, ws, &turnRequest); err != nil {
					serverErrors <- err
					return
				}
				if err := wsjson.Write(ctx, ws, jsonRPCMessage{
					JSONRPC: jsonRPCVersion,
					ID:      turnRequest.ID,
					Result:  json.RawMessage(`{"ExpirationInSeconds":60}`),
				}); err != nil {
					serverErrors <- err
					return
				}
				var outgoing jsonRPCMessage
				if err := wsjson.Read(ctx, ws, &outgoing); err != nil {
					serverErrors <- err
					return
				}
				if serviceAccepted {
					if err := wsjson.Write(ctx, ws, jsonRPCMessage{
						JSONRPC: jsonRPCVersion, ID: outgoing.ID, Result: json.RawMessage("null"),
					}); err != nil {
						serverErrors <- err
						return
					}
				}
				inner, _ := json.Marshal(jsonRPCDeliveryError{Code: 1, Message: failureText})
				params, _ := json.Marshal(map[string]any{
					"From": "0123456789ABCDEF", "Message": string(inner), "Id": uuid.NewString(),
				})
				if err := wsjson.Write(ctx, ws, jsonRPCMessage{
					JSONRPC: jsonRPCVersion, ID: json.RawMessage("17"), Method: methodReceiveMessage, Params: params,
				}); err != nil {
					serverErrors <- err
					return
				}
				var ack jsonRPCMessage
				if err := wsjson.Read(ctx, ws, &ack); err != nil {
					serverErrors <- err
					return
				}
				serverMessages <- ack
				// Read the close frame, completing the client's close handshake.
				_, _, _ = ws.Read(ctx)
			}))
			defer server.Close()

			conn, err := (JSONRPCDialer{Host: server.URL, KeepAlive: time.Hour}).DialContext(
				ctx, &authservice.MCToken{AuthorizationHeader: "MCToken test"},
			)
			if err != nil {
				t.Fatal(err)
			}
			defer conn.Close()
			if _, err := conn.Credentials(ctx); err != nil {
				t.Fatal(err)
			}
			err = conn.Signal(ctx, &nethernet.Signal{
				Type: nethernet.SignalTypeOffer, ConnectionID: 42, Data: "offer-sdp",
				NetworkID: "00000000-0000-0000-0000-000000000001",
			})
			var deliveryErr *jsonRPCDeliveryError
			if (!serviceAccepted || err != nil) && (!errors.As(err, &deliveryErr) || deliveryErr.Message != failureText) {
				t.Fatalf("Signal error = %v, want delivery error", err)
			}
			select {
			case <-conn.Context().Done():
				cause := context.Cause(conn.Context())
				if !errors.As(cause, &deliveryErr) || deliveryErr.Code != 1 || deliveryErr.Message != failureText {
					t.Fatalf("signaling stopped with %v, want original delivery error", cause)
				}
			case <-ctx.Done():
				t.Fatal("delivery error left negotiation waiting")
			}
			ack := receiveServerMessage(t, serverMessages, serverErrors)
			if string(ack.ID) != "17" || string(ack.Result) != "null" {
				t.Fatalf("delivery failure was not acknowledged: %#v", ack)
			}
		})
	}
}
