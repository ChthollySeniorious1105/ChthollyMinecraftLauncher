package resourcepacks

import (
	"context"
	"testing"

	"github.com/google/uuid"
	"github.com/sandertv/gophertunnel/minecraft/protocol"
	"github.com/sandertv/gophertunnel/minecraft/protocol/packet"
)

func TestParseResourcePackUUID(t *testing.T) {
	t.Parallel()

	const id = "0fba4063-dba1-4281-9b89-ff9390653530"
	want := uuid.MustParse(id)
	tests := []struct {
		name    string
		value   string
		wantErr bool
	}{
		{name: "plain UUID", value: id},
		{name: "UUID with version", value: id + "_1.0.0"},
		{name: "invalid UUID", value: "not-a-uuid_1.0.0", wantErr: true},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, err := parseResourcePackUUID(tt.value)
			if tt.wantErr {
				if err == nil {
					t.Fatalf("parseResourcePackUUID(%q) unexpectedly succeeded", tt.value)
				}
				return
			}
			if err != nil {
				t.Fatalf("parseResourcePackUUID(%q) error = %v", tt.value, err)
			}
			if got != want {
				t.Fatalf("parseResourcePackUUID(%q) = %v, want %v", tt.value, got, want)
			}
		})
	}
}

func TestParseResourcePackKey(t *testing.T) {
	t.Parallel()

	const id = "0fba4063-dba1-4281-9b89-ff9390653530"
	gotID, gotVersion, err := parseResourcePackKey(id + "_1.0.0")
	if err != nil {
		t.Fatalf("parseResourcePackKey() error = %v", err)
	}
	if want := uuid.MustParse(id); gotID != want {
		t.Fatalf("parseResourcePackKey() UUID = %v, want %v", gotID, want)
	}
	if gotVersion != "1.0.0" {
		t.Fatalf("parseResourcePackKey() version = %q, want %q", gotVersion, "1.0.0")
	}

	for _, value := range []string{id, id + "_", "not-a-uuid_1.0.0"} {
		if _, _, err := parseResourcePackKey(value); err == nil {
			t.Fatalf("parseResourcePackKey(%q) unexpectedly succeeded", value)
		}
	}
}

func TestBuiltInResourcePackIsExempt(t *testing.T) {
	t.Parallel()

	handler := &ResourcePackHandler{}
	id := uuid.MustParse("d34cfa4b-2ad1-453d-a0db-668b429a3ea0")
	if !handler.hasPack(id, "1.26.40") {
		t.Fatal("1.26.40 built-in resource pack was not exempt")
	}
}

func TestBuiltInResourcePackIsNotForwarded(t *testing.T) {
	t.Parallel()

	builtIn := protocol.TexturePackInfo{
		UUID:    uuid.MustParse("d34cfa4b-2ad1-453d-a0db-668b429a3ea0"),
		Version: "1.26.40",
	}
	regular := protocol.TexturePackInfo{
		UUID:    uuid.MustParse("0ec1d0f9-a5ad-48bd-9be7-e75f38a8edf4"),
		Version: "1.0.0",
	}
	got := resourcePacksForClient([]protocol.TexturePackInfo{builtIn, regular})
	if len(got) != 1 || got[0].UUID != regular.UUID || got[0].Version != regular.Version {
		t.Fatalf("filtered packs = %#v, want only %#v", got, regular)
	}
}

func TestGetResourcePacksInfoPreservesCurrentFields(t *testing.T) {
	t.Parallel()

	received := make(chan struct{})
	close(received)
	wantPack := protocol.TexturePackInfo{
		UUID:    uuid.MustParse("0ec1d0f9-a5ad-48bd-9be7-e75f38a8edf4"),
		Version: "1.0.0",
	}
	want := &packet.ResourcePacksInfo{
		TexturePackRequired:        true,
		HasAddons:                  true,
		HasScripts:                 true,
		ForceDisableVibrantVisuals: true,
		WorldTemplateUUID:          uuid.MustParse("18ea3cbd-c3f2-40f2-86da-3addf7b8e223"),
		WorldTemplateVersion:       "2.5.0",
		TexturePacks:               []protocol.TexturePackInfo{wantPack},
	}
	handler := &ResourcePackHandler{
		ctx:                    context.Background(),
		receivedRemotePackInfo: received,
		remotePacksInfo:        want,
	}

	got := handler.GetResourcePacksInfo(false)
	if got.TexturePackRequired != want.TexturePackRequired ||
		got.HasAddons != want.HasAddons ||
		got.HasScripts != want.HasScripts ||
		got.ForceDisableVibrantVisuals != want.ForceDisableVibrantVisuals ||
		got.WorldTemplateUUID != want.WorldTemplateUUID ||
		got.WorldTemplateVersion != want.WorldTemplateVersion ||
		len(got.TexturePacks) != 1 || got.TexturePacks[0].UUID != wantPack.UUID {
		t.Fatalf("GetResourcePacksInfo() = %#v, want fields from %#v", got, want)
	}

	got.TexturePacks[0].Version = "changed"
	if want.TexturePacks[0].Version != wantPack.Version {
		t.Fatal("GetResourcePacksInfo() returned an aliased TexturePacks slice")
	}
}
