package minecraft

import (
	"context"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"errors"
	"net"
	"testing"
)

var (
	errOrdinaryDial = errors.New("ordinary dial called")
	errIdentityDial = errors.New("identity dial called")
)

type identityTestNetwork struct {
	identityCalled bool
	address        string
	token          string
	privateKey     *ecdsa.PrivateKey
}

func (*identityTestNetwork) DialContext(context.Context, string) (net.Conn, error) {
	return nil, errOrdinaryDial
}

func (n *identityTestNetwork) DialContextIdentity(_ context.Context, address, token string, privateKey *ecdsa.PrivateKey) (net.Conn, error) {
	n.identityCalled = true
	n.address = address
	n.token = token
	n.privateKey = privateKey
	return nil, errIdentityDial
}

func (*identityTestNetwork) PingContext(context.Context, string) ([]byte, error) {
	return nil, errors.New("ping not supported")
}

func (*identityTestNetwork) Listen(string) (NetworkListener, error) {
	return nil, errors.New("listen not supported")
}

func TestDialNetworkContextUsesIdentityDialer(t *testing.T) {
	privateKey, err := ecdsa.GenerateKey(elliptic.P384(), rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	network := &identityTestNetwork{}
	_, err = dialNetworkContext(context.Background(), network, "remote-player-id", "multiplayer-token", privateKey)
	if !errors.Is(err, errIdentityDial) {
		t.Fatalf("dialNetworkContext() error = %v, want %v", err, errIdentityDial)
	}
	if !network.identityCalled {
		t.Fatal("DialContextIdentity was not called")
	}
	if network.address != "remote-player-id" || network.token != "multiplayer-token" || network.privateKey != privateKey {
		t.Fatal("DialContextIdentity did not receive the login address, token and private key unchanged")
	}
}

func TestDialNetworkContextFallsBackWithoutToken(t *testing.T) {
	network := &identityTestNetwork{}
	_, err := dialNetworkContext(context.Background(), network, "remote-player-id", "", nil)
	if !errors.Is(err, errOrdinaryDial) {
		t.Fatalf("dialNetworkContext() error = %v, want %v", err, errOrdinaryDial)
	}
	if network.identityCalled {
		t.Fatal("DialContextIdentity was called without a multiplayer token")
	}
}
