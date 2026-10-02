package proxy

import (
	"context"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"encoding/base64"
	"encoding/json"
	"errors"
	"strings"
	"testing"

	"github.com/df-mc/go-nethernet"
	"github.com/go-jose/go-jose/v4"
)

var errOfferCaptured = errors.New("offer captured")

type captureSignaling struct {
	ctx   context.Context
	offer string
}

func (s *captureSignaling) Signal(_ context.Context, signal *nethernet.Signal) error {
	if signal.Type == nethernet.SignalTypeOffer {
		s.offer = signal.Data
		return errOfferCaptured
	}
	return nil
}

func (*captureSignaling) Notify(nethernet.Notifier) func() { return func() {} }
func (s *captureSignaling) Context() context.Context       { return s.ctx }
func (*captureSignaling) Credentials(context.Context) (*nethernet.Credentials, error) {
	return nil, nil
}
func (*captureSignaling) NetworkID() string { return "local-network-id" }
func (*captureSignaling) PongData([]byte)   {}

func TestNetherNetDialContextIdentityAddsIdentityAssertion(t *testing.T) {
	privateKey, err := ecdsa.GenerateKey(elliptic.P384(), rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	signaling := &captureSignaling{ctx: context.Background()}
	const (
		domain = "https://authorization.franchise.minecraft-services.net/"
		token  = "header.payload.signature"
	)
	network := NetherNet{
		Signaling:      signaling,
		IdentityDomain: domain,
	}

	_, err = network.DialContextIdentity(context.Background(), "remote-player-id", token, privateKey)
	if !errors.Is(err, errOfferCaptured) {
		t.Fatalf("DialContextIdentity() error = %v, want %v", err, errOfferCaptured)
	}

	encoded := identityAttribute(signaling.offer)
	if encoded == "" {
		t.Fatal("CONNECTREQUEST offer does not contain an a=identity attribute")
	}
	if identityIndex, mediaIndex := strings.Index(signaling.offer, "a=identity:"), strings.Index(signaling.offer, "m="); mediaIndex >= 0 && identityIndex > mediaIndex {
		t.Fatal("a=identity must be a session-level SDP attribute")
	}
	b, err := base64.StdEncoding.DecodeString(encoded)
	if err != nil {
		t.Fatalf("decode identity attribute: %v", err)
	}
	var identity struct {
		Assertion string `json:"assertion"`
		IDP       struct {
			Domain   string `json:"domain"`
			Protocol string `json:"protocol"`
		} `json:"idp"`
	}
	if err := json.Unmarshal(b, &identity); err != nil {
		t.Fatalf("decode identity envelope: %v", err)
	}
	if identity.IDP.Domain != domain || identity.IDP.Protocol != "default" {
		t.Fatalf("unexpected identity provider: domain=%q protocol=%q", identity.IDP.Domain, identity.IDP.Protocol)
	}
	var assertion struct {
		Fingerprints string `json:"fingerprints"`
		Token        string `json:"token"`
	}
	if err := json.Unmarshal([]byte(identity.Assertion), &assertion); err != nil {
		t.Fatalf("decode nested identity assertion: %v", err)
	}
	if assertion.Token != token {
		t.Fatal("identity assertion did not preserve the multiplayer session token")
	}
	parts := strings.Split(assertion.Fingerprints, ".")
	if len(parts) != 3 || parts[1] != "" {
		t.Fatalf("fingerprint assertion is not a detached JWS")
	}
	fingerprints := sdpFingerprints(signaling.offer)
	if len(fingerprints) == 0 {
		t.Fatal("CONNECTREQUEST offer does not contain a DTLS fingerprint")
	}
	payload, err := json.Marshal(struct {
		Fingerprint []sdpFingerprint `json:"fingerprint"`
	}{Fingerprint: fingerprints})
	if err != nil {
		t.Fatal(err)
	}
	signature, err := jose.ParseDetached(assertion.Fingerprints, payload, []jose.SignatureAlgorithm{jose.ES384})
	if err != nil {
		t.Fatalf("parse detached fingerprint assertion: %v", err)
	}
	if _, err := signature.Verify(&privateKey.PublicKey); err != nil {
		t.Fatalf("verify fingerprint assertion with login public key: %v", err)
	}
}

func identityAttribute(offer string) string {
	for _, line := range strings.Split(offer, "\n") {
		line = strings.TrimSuffix(line, "\r")
		if value, ok := strings.CutPrefix(line, "a=identity:"); ok {
			return value
		}
	}
	return ""
}

type sdpFingerprint struct {
	Algorithm string `json:"algorithm"`
	Digest    string `json:"digest"`
}

func sdpFingerprints(offer string) []sdpFingerprint {
	var fingerprints []sdpFingerprint
	for _, line := range strings.Split(offer, "\n") {
		line = strings.TrimSuffix(line, "\r")
		value, ok := strings.CutPrefix(line, "a=fingerprint:")
		if !ok {
			continue
		}
		algorithm, digest, ok := strings.Cut(value, " ")
		if ok {
			fingerprints = append(fingerprints, sdpFingerprint{Algorithm: algorithm, Digest: digest})
		}
	}
	return fingerprints
}

func TestNetherNetDialContextIdentityValidatesInputs(t *testing.T) {
	tests := []struct {
		name    string
		token   string
		key     *ecdsa.PrivateKey
		domain  string
		wantErr string
	}{
		{name: "private key", token: "token", domain: "https://issuer/", wantErr: "private key is nil"},
		{name: "token", key: &ecdsa.PrivateKey{}, domain: "https://issuer/", wantErr: "token is empty"},
		{name: "domain", token: "token", key: &ecdsa.PrivateKey{}, wantErr: "identity domain is empty"},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			network := NetherNet{
				Signaling:      &captureSignaling{ctx: context.Background()},
				IdentityDomain: test.domain,
			}
			_, err := network.DialContextIdentity(context.Background(), "remote", test.token, test.key)
			if err == nil || !strings.Contains(err.Error(), test.wantErr) {
				t.Fatalf("DialContextIdentity() error = %v, want error containing %q", err, test.wantErr)
			}
		})
	}
}
