package worlds

import (
	"testing"
	"time"

	"github.com/bedrock-tool/bedrocktool/utils/behaviourpack"
	"github.com/df-mc/dragonfly/server/world"
	"github.com/sandertv/gophertunnel/minecraft/protocol"
	"github.com/sandertv/gophertunnel/minecraft/protocol/packet"
)

// A server can send biomes this build doesn't know (new game versions add them, e.g. 26.50's
// dappled_forest). They used to all register with ID 0 and panic on the second one.
func TestBiomeDefinitionListUnknownBiomes(t *testing.T) {
	w := &worldsHandler{}
	w.serverState.biomes = world.DefaultBiomes.Clone()
	w.serverState.behaviorPack = behaviourpack.New("test")

	plains, ok := world.DefaultBiomes.BiomeByName("plains")
	if !ok {
		t.Fatal("plains missing from default registry")
	}
	pk := &packet.BiomeDefinitionList{
		StringList: []string{"minecraft:dappled_forest", "minecraft:future_biome", "custom:taken_id", "minecraft:plains"},
		BiomeDefinitions: []protocol.BiomeDefinition{
			{NameIndex: 0, BiomeID: 30001},
			{NameIndex: 1, BiomeID: 30002},
			{NameIndex: 2, BiomeID: int16(plains.EncodeBiome())}, // collides with a known biome's ID
			{NameIndex: 3, BiomeID: int16(plains.EncodeBiome())}, // known biome: left alone
		},
	}
	if _, err := w.packetHandlerPreLogin(pk, time.Time{}); err != nil {
		t.Fatal(err)
	}

	for name, id := range map[string]int{"dappled_forest": 30001, "future_biome": 30002} {
		b, ok := w.serverState.biomes.BiomeByName(name)
		if !ok {
			t.Fatalf("%s not registered", name)
		}
		if b.EncodeBiome() != id {
			t.Fatalf("%s registered with ID %d, want %d", name, b.EncodeBiome(), id)
		}
	}
	if _, ok := w.serverState.biomes.BiomeByName("custom:taken_id"); ok {
		t.Fatal("biome with an already-used ID must be skipped")
	}
	if b, _ := w.serverState.biomes.BiomeByID(plains.EncodeBiome()); b.String() != plains.String() {
		t.Fatalf("plains was replaced by %s", b.String())
	}

	// a second list (e.g. after a dimension change) must not panic either
	if _, err := w.packetHandlerPreLogin(pk, time.Time{}); err != nil {
		t.Fatal(err)
	}
}
