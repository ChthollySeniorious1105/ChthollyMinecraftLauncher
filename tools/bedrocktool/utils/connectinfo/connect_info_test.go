package connectinfo

import (
	"testing"

	"github.com/bedrock-tool/bedrocktool/utils/franchise/gatherings"
	"github.com/sandertv/gophertunnel/minecraft/realms"
)

func TestParseConnectInfo(t *testing.T) {
	type test struct {
		value    string
		expected parsedConnectInfo
	}
	var tests = []test{
		{value: "minecraft.net", expected: parsedConnectInfo{serverAddress: "minecraft.net:19132"}},
		{value: "realm:test-realm", expected: parsedConnectInfo{realmName: "test-realm"}},
		{value: "gathering:test-gathering", expected: parsedConnectInfo{gatheringName: "test-gathering"}},
		{value: "test-capture.pcap2", expected: parsedConnectInfo{replayName: "test-capture.pcap2"}},
	}

	for _, tt := range tests {
		r, err := parseConnectInfo(tt.value)
		if err != nil {
			t.Fatal(err)
		}
		if *r != tt.expected {
			t.Fatalf("%s expected: %v\ngot: %v\n", tt.value, tt.expected, r)
		}
	}
}

func TestParseNetherNetConnectInfo(t *testing.T) {
	tests := []struct {
		value     string
		id        string
		signaling SignalingProtocol
	}{
		{value: "nethernet:123456789", id: "123456789", signaling: SignalingLegacy},
		{value: "nethernet-jsonrpc:bfad0322-9335-4845-ab6c-0dafe56ee3a2", id: "bfad0322-9335-4845-ab6c-0dafe56ee3a2", signaling: SignalingJSONRPC},
	}
	for _, test := range tests {
		t.Run(test.value, func(t *testing.T) {
			info, err := parseConnectInfo(test.value)
			if err != nil {
				t.Fatal(err)
			}
			if info.netherNet != test.id || info.netherNetSignaling != test.signaling {
				t.Fatalf("got ID %q and signaling %q", info.netherNet, info.netherNetSignaling)
			}
		})
	}
}

func TestTargetForRealmAddress(t *testing.T) {
	jsonRPCAddress := realms.RealmAddress{
		Address:         "bfad0322-9335-4845-ab6c-0dafe56ee3a2",
		NetworkProtocol: realms.NetworkProtocolNetherNetJSONRPC,
	}
	jsonRPCAddress.SessionRegionData.RegionName = "WestUS"

	tests := []struct {
		name    string
		address realms.RealmAddress
		want    Target
	}{
		{
			name:    "raknet",
			address: realms.RealmAddress{Address: "example.net:19132", NetworkProtocol: realms.NetworkProtocolDefault},
			want:    Target{Network: NetworkRakNet, Address: "example.net:19132"},
		},
		{
			name:    "legacy nethernet",
			address: realms.RealmAddress{Address: "123456789", NetworkProtocol: realms.NetworkProtocolNetherNet},
			want:    Target{Network: NetworkNetherNet, Address: "123456789", Signaling: SignalingLegacy},
		},
		{
			name:    "jsonrpc nethernet",
			address: jsonRPCAddress,
			want: Target{
				Network:       NetworkNetherNet,
				Address:       "bfad0322-9335-4845-ab6c-0dafe56ee3a2",
				Signaling:     SignalingJSONRPC,
				SignalingHost: "signal-westus.franchise.minecraft-services.net",
			},
		},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			got, err := targetForRealmAddress(test.address)
			if err != nil {
				t.Fatal(err)
			}
			if got != test.want {
				t.Fatalf("got %#v, want %#v", got, test.want)
			}
		})
	}
}

func TestTargetForRealmAddressRejectsUnknownProtocol(t *testing.T) {
	_, err := targetForRealmAddress(realms.RealmAddress{
		Address:         "bfad0322-9335-4845-ab6c-0dafe56ee3a2",
		NetworkProtocol: "FUTURE_PROTOCOL",
	})
	if err == nil {
		t.Fatal("expected unsupported protocol error")
	}
}

func TestTargetForFranchiseAddress(t *testing.T) {
	tests := []struct {
		name    string
		address gatherings.ConnectionAddress
		want    Target
	}{
		{
			name:    "raknet host and port",
			address: gatherings.ConnectionAddress{Address: "featured.example", Port: 19132},
			want:    Target{Network: NetworkRakNet, Address: "featured.example:19132"},
		},
		{
			name: "jsonrpc GUID",
			address: gatherings.ConnectionAddress{
				NetworkProtocol: string(realms.NetworkProtocolNetherNetJSONRPC),
				Address:         "bfad0322-9335-4845-ab6c-0dafe56ee3a2",
			},
			want: Target{
				Network:       NetworkNetherNet,
				Address:       "bfad0322-9335-4845-ab6c-0dafe56ee3a2",
				Signaling:     SignalingJSONRPC,
				SignalingHost: "signal.franchise.minecraft-services.net",
			},
		},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			got, err := targetForFranchiseAddress(test.address)
			if err != nil {
				t.Fatal(err)
			}
			if got != test.want {
				t.Fatalf("got %#v, want %#v", got, test.want)
			}
		})
	}
}
