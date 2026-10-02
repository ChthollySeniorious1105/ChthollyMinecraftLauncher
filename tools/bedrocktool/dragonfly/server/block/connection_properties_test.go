package block

import (
	"testing"

	"github.com/df-mc/dragonfly/server/item"
	"github.com/df-mc/dragonfly/server/world"
)

// TestConnectedStateRoundTrip guards the 26.50 block registry additions. The
// local block implementations expose the default disconnected state while the
// registry must still accept every connection property emitted by Bedrock.
func TestConnectedStateRoundTrip(t *testing.T) {
	world.DefaultBlockRegistry.Finalize()

	blocks := []world.Block{
		GlassPane{},
		StainedGlassPane{Colour: item.ColourWhite()},
		IronBars{},
		NetherBrickFence{},
		String{},
	}
	for _, b := range blocks {
		name, properties := b.EncodeBlock()
		properties["minecraft:connection_north"] = true

		rid, ok := world.DefaultBlockRegistry.StateToRuntimeID(name, properties)
		if !ok {
			t.Fatalf("state was not registered for %s: %#v", name, properties)
		}
		_, encoded, ok := world.DefaultBlockRegistry.RuntimeIDToState(rid)
		if !ok || encoded["minecraft:connection_north"] != uint8(1) {
			t.Fatalf("registered state did not round-trip for %s: %#v", name, encoded)
		}
	}
}
