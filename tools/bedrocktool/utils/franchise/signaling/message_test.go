package signaling

import (
	"context"
	"encoding/json"
	"strings"
	"testing"
	"time"

	"github.com/df-mc/go-nethernet"
)

func TestMessageNetworkIDEncoding(t *testing.T) {
	numeric, err := json.Marshal(Message{Type: MessageTypeSignal, To: "123456789"})
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(numeric), `"To":123456789`) {
		t.Fatalf("numeric network ID was not encoded as a number: %s", numeric)
	}

	guid, err := json.Marshal(Message{Type: MessageTypeSignal, To: "bfad0322-9335-4845-ab6c-0dafe56ee3a2"})
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(guid), `"To":"bfad0322-9335-4845-ab6c-0dafe56ee3a2"`) {
		t.Fatalf("GUID network ID was not encoded as a string: %s", guid)
	}
}

func TestLegacyCredentialsWaitsForCredentials(t *testing.T) {
	signalingCtx, cancel := context.WithCancelCause(context.Background())
	defer cancel(nil)
	c := &Conn{
		ctx:                 signalingCtx,
		closed:              make(chan struct{}),
		credentialsReceived: make(chan struct{}),
	}

	result := make(chan *nethernet.Credentials, 1)
	go func() {
		credentials, _ := c.Credentials(context.Background())
		result <- credentials
	}()

	select {
	case <-result:
		t.Fatal("Credentials returned before credentials were available")
	case <-time.After(20 * time.Millisecond):
	}

	want := &nethernet.Credentials{ExpirationInSeconds: 3600}
	c.credentials.Store(want)
	close(c.credentialsReceived)
	select {
	case got := <-result:
		if got != want {
			t.Fatalf("got %#v, want %#v", got, want)
		}
	case <-time.After(time.Second):
		t.Fatal("Credentials did not unblock")
	}
}
