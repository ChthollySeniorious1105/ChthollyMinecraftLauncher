package merge

import "testing"

func TestNetworkBlockHashLink(t *testing.T) {
	got := networkBlockHash("minecraft:bamboo_hanging_sign", map[string]any{
		"facing_direction":      int32(3),
		"ground_sign_direction": int32(9),
		"attached_bit":          byte(1),
		"hanging":               byte(0),
	})
	if want := uint32(0x090ec6ed); got != want {
		t.Fatalf("network block hash = %#08x, want %#08x", got, want)
	}
}
