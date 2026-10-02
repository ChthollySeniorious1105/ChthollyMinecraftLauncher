package proxy

import (
	"context"
	"crypto/ecdsa"
	"errors"
	"fmt"
	"net"

	"github.com/df-mc/go-nethernet"
	"github.com/sandertv/gophertunnel/minecraft"
)

// NetherNet is an implementation of NetherNet network. Unlike RakNet, it needs to be registered manually with a Signaling.
type NetherNet struct {
	Signaling      nethernet.Signaling
	IdentityDomain string

	// Dialer specifies options for establishing a connection with DialContext.
	Dialer nethernet.Dialer
	// ListenConfig specifies options for listening for connections with Listen.
	ListenConfig nethernet.ListenConfig
}

// DialContext ...
func (n NetherNet) DialContext(ctx context.Context, address string) (net.Conn, error) {
	if n.Signaling == nil {
		return nil, errors.New("minecraft: NetherNet.DialContext: Signaling is nil")
	}
	return n.Dialer.DialContext(ctx, address, n.Signaling)
}

// DialContextIdentity establishes a NetherNet connection with the authenticated
// identity already obtained for the Minecraft login. Using the same token and
// private key binds the SDP fingerprint to the player's cpk claim.
func (n NetherNet) DialContextIdentity(ctx context.Context, address, token string, privateKey *ecdsa.PrivateKey) (net.Conn, error) {
	if n.Dialer.Identity == nil {
		if privateKey == nil {
			return nil, fmt.Errorf("minecraft: NetherNet.DialContextIdentity: private key is nil")
		}
		if token == "" {
			return nil, fmt.Errorf("minecraft: NetherNet.DialContextIdentity: token is empty")
		}
		if n.IdentityDomain == "" {
			return nil, fmt.Errorf("minecraft: NetherNet.DialContextIdentity: identity domain is empty")
		}
		n.Dialer.Identity = &nethernet.Identity{
			PrivateKey: privateKey,
			Token:      token,
			Domain:     n.IdentityDomain,
		}
	}
	return n.DialContext(ctx, address)
}

// PingContext ...
func (n NetherNet) PingContext(context.Context, string) ([]byte, error) {
	return nil, errors.New("minecraft: NetherNet.PingContext: not supported")
}

// Listen ...
func (n NetherNet) Listen(string) (minecraft.NetworkListener, error) {
	if n.Signaling == nil {
		return nil, errors.New("minecraft: NetherNet.Listen: Signaling is nil")
	}
	return n.ListenConfig.Listen(n.Signaling)
}
