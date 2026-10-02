package world

import (
	"fmt"
	"testing"
)

func TestNetworkHash(t *testing.T) {
	hash, _ := networkBlockHash("minecraft:bamboo_hanging_sign", map[string]any{
		"facing_direction":      int32(3),
		"ground_sign_direction": int32(9),
		"attached_bit":          byte(1),
		"hanging":               byte(0),
	}, nil)

	fmt.Printf("%08x\n", hash)

	if hash != 0x090ec6ed {
		t.Fail()
	}
}
