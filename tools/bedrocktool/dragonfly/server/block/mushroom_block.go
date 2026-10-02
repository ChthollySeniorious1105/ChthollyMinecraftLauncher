package block

import "github.com/df-mc/dragonfly/server/world"

// MushroomBlock is a solid block that makes up a huge mushroom
type MushroomBlock struct {
	solid

	// Type is the type of mushroomblock
	Type     MushroomType
	HugeBits int
}

// BreakInfo ...
func (m MushroomBlock) BreakInfo() BreakInfo {
	return newBreakInfo(0.2, alwaysHarvestable, axeEffective, oneOf(m))
}

// EncodeItem ...
func (m MushroomBlock) EncodeItem() (name string, meta int16) {
	return "minecraft:" + m.Type.String() + "_mushroom_block", 0
}

// EncodeBlock ...
func (m MushroomBlock) EncodeBlock() (string, map[string]any) {
	return "minecraft:" + m.Type.String() + "_mushroom_block", map[string]any{
		"huge_mushroom_bits": int32(m.HugeBits),
	}
}

func allMushroomBlock() (s []world.Block) {
	for _, t := range MushroomTypes() {
		for i := 0; i < 16; i++ {
			s = append(s, MushroomBlock{Type: t, HugeBits: i})
		}
	}
	return
}
