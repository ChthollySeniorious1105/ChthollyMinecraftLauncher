package auth

import (
	"context"
	"encoding/json"
	"testing"

	"github.com/bedrock-tool/bedrocktool/utils/franchise/discovery"
	"github.com/bedrock-tool/bedrocktool/utils/franchise/gatherings"
)

func TestNetherNetIdentityDomain(t *testing.T) {
	tests := []struct {
		name   string
		issuer string
		want   string
	}{
		{
			name:   "adds trailing slash",
			issuer: "https://authorization.franchise.minecraft-services.net",
			want:   "https://authorization.franchise.minecraft-services.net/",
		},
		{
			name:   "preserves trailing slash",
			issuer: "https://authorization.franchise.minecraft-services.net/",
			want:   "https://authorization.franchise.minecraft-services.net/",
		},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			a := &Account{discovery: &discovery.Discovery{
				Env: "prod",
				ServiceEnvironments: map[string]map[string]json.RawMessage{
					"auth": {
						"prod": json.RawMessage(`{"serviceUri":"https://authorization.example","issuer":"` + test.issuer + `"}`),
					},
				},
			}}

			got, err := a.NetherNetIdentityDomain(context.Background())
			if err != nil {
				t.Fatal(err)
			}
			if got != test.want {
				t.Fatalf("NetherNetIdentityDomain() = %q, want %q", got, test.want)
			}
		})
	}
}

func TestNetherNetIdentityDomainRejectsInvalidIssuer(t *testing.T) {
	a := &Account{discovery: &discovery.Discovery{
		Env: "prod",
		ServiceEnvironments: map[string]map[string]json.RawMessage{
			"auth": {
				"prod": json.RawMessage(`{"serviceUri":"https://authorization.example","issuer":"not-a-url"}`),
			},
		},
	}}
	if _, err := a.NetherNetIdentityDomain(context.Background()); err == nil {
		t.Fatal("NetherNetIdentityDomain() succeeded with an invalid issuer")
	}
}

func TestSignalingInitializesIndependentlyFromGatherings(t *testing.T) {
	a := &Account{
		gatherings: &gatherings.GatheringsService{},
		discovery: &discovery.Discovery{
			Env: "prod",
			ServiceEnvironments: map[string]map[string]json.RawMessage{
				"signaling": {
					"prod": json.RawMessage(`{"serviceUri":"https://signal.example","stunUri":"stun:example","turnUri":"turn:example"}`),
				},
			},
		},
	}

	service, err := a.Signaling(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	if service == nil || service.Config.ServiceURI != "https://signal.example" {
		t.Fatalf("unexpected signaling service: %#v", service)
	}
}
