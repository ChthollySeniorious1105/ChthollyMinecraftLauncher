package block

import (
	"image/color"

	"github.com/df-mc/dragonfly/server/item"
)

func (Amethyst) Color() color.RGBA {
	return color.RGBA{122, 91, 181, 255}
}

func (AncientDebris) Color() color.RGBA {
	return color.RGBA{93, 52, 44, 255}
}

func (Anvil) Color() color.RGBA {
	return color.RGBA{74, 74, 74, 255}
}

func (a Azalea) Color() color.RGBA {
	if a.Flowering {
		return color.RGBA{173, 91, 192, 255}
	} else {
		return color.RGBA{104, 136, 42, 255}
	}
}

func (Banner) Color() color.RGBA {
	return color.RGBA{184, 148, 95, 255}
}

func (Barrel) Color() color.RGBA {
	return color.RGBA{128, 94, 60, 255}
}

func (Basalt) Color() color.RGBA {
	return color.RGBA{79, 75, 79, 255}
}

func (Beacon) Color() color.RGBA {
	return color.RGBA{73, 213, 204, 255}
}

func (Bedrock) Color() color.RGBA {
	return color.RGBA{87, 87, 87, 255}
}

func (BeetrootSeeds) Color() color.RGBA {
	return color.RGBA{74, 143, 42, 255}
}

func (Blackstone) Color() color.RGBA {
	return color.RGBA{32, 19, 28, 255}
}

func (BlastFurnace) Color() color.RGBA {
	return color.RGBA{73, 72, 72, 255}
}

func (transparent) Color() color.RGBA {
	return color.RGBA{0, 0, 0, 0}
}

func (BlueIce) Color() color.RGBA {
	return color.RGBA{108, 163, 253, 255}
}

func (Bone) Color() color.RGBA {
	return color.RGBA{201, 197, 167, 255}
}

func (Bookshelf) Color() color.RGBA {
	return color.RGBA{179, 140, 98, 255}
}

func (Bricks) Color() color.RGBA {
	return color.RGBA{169, 110, 103, 255}
}

func (Cactus) Color() color.RGBA {
	return color.RGBA{73, 90, 36, 255}
}

func (Cake) Color() color.RGBA {
	return color.RGBA{255, 253, 254, 255}
}

func (Calcite) Color() color.RGBA {
	return color.RGBA{201, 201, 196, 255}
}

func (c Candle) Color() color.RGBA {
	if !c.Dyed {
		return color.RGBA{254, 240, 179, 255}
	}
	switch c.Colour {
	case item.ColourWhite():
		return color.RGBA{224, 229, 229, 255}
	case item.ColourOrange():
		return color.RGBA{230, 101, 0, 255}
	case item.ColourMagenta():
		return color.RGBA{186, 47, 166, 255}
	case item.ColourLightBlue():
		return color.RGBA{32, 141, 205, 255}
	case item.ColourYellow():
		return color.RGBA{218, 171, 52, 255}
	case item.ColourPink():
		return color.RGBA{222, 101, 148, 255}
	case item.ColourLime():
		return color.RGBA{222, 101, 148, 255}
	case item.ColourGrey():
		return color.RGBA{82, 97, 98, 255}
	case item.ColourLightGrey():
		return color.RGBA{125, 127, 119, 255}
	case item.ColourCyan():
		return color.RGBA{18, 158, 157, 255}
	case item.ColourPurple():
		return color.RGBA{106, 36, 164, 255}
	case item.ColourBlue():
		return color.RGBA{64, 90, 190, 255}
	case item.ColourBrown():
		return color.RGBA{114, 71, 40, 255}
	case item.ColourGreen():
		return color.RGBA{96, 129, 22, 255}
	case item.ColourRed():
		return color.RGBA{162, 39, 41, 255}
	case item.ColourBlack():
		return color.RGBA{39, 38, 61, 255}
	}
	return color.RGBA{255, 0, 255, 255}
}

func (c Carpet) Color() color.RGBA {
	switch c.Colour {
	case item.ColourWhite():
		return color.RGBA{248, 249, 249, 255}
	case item.ColourOrange():
		return color.RGBA{249, 130, 30, 255}
	case item.ColourMagenta():
		return color.RGBA{186, 65, 175, 255}
	case item.ColourLightBlue():
		return color.RGBA{72, 193, 228, 255}
	case item.ColourYellow():
		return color.RGBA{253, 211, 52, 255}
	case item.ColourLime():
		return color.RGBA{123, 195, 27, 255}
	case item.ColourPink():
		return color.RGBA{243, 138, 170, 255}
	case item.ColourGrey():
		return color.RGBA{67, 73, 76, 255}
	case item.ColourLightGrey():
		return color.RGBA{149, 149, 143, 255}
	case item.ColourCyan():
		return color.RGBA{21, 127, 140, 255}
	case item.ColourPurple():
		return color.RGBA{108, 34, 161, 255}
	case item.ColourBlue():
		return color.RGBA{52, 54, 154, 255}
	case item.ColourBrown():
		return color.RGBA{124, 78, 46, 255}
	case item.ColourGreen():
		return color.RGBA{89, 117, 24, 255}
	case item.ColourRed():
		return color.RGBA{172, 43, 36, 255}
	case item.ColourBlack():
		return color.RGBA{26, 26, 30, 255}
	}
	return color.RGBA{255, 0, 255, 255}
}

func (Carrot) Color() color.RGBA {
	return color.RGBA{43, 112, 40, 255}
}

func (IronChain) Color() color.RGBA {
	return color.RGBA{37, 44, 61, 255}
}

func (Chest) Color() color.RGBA {
	return color.RGBA{167, 114, 39, 255}
}

func (Clay) Color() color.RGBA {
	return color.RGBA{161, 167, 179, 255}
}

func (CoalOre) Color() color.RGBA {
	return color.RGBA{116, 116, 116, 255}
}

func (Coal) Color() color.RGBA {
	return color.RGBA{21, 21, 21, 255}
}

func (Cobblestone) Color() color.RGBA {
	return color.RGBA{166, 166, 166, 255}
}

func (CocoaBean) Color() color.RGBA {
	return color.RGBA{130, 60, 14, 255}
}

func (c ConcretePowder) Color() color.RGBA {
	switch c.Colour {
	case item.ColourWhite():
		return color.RGBA{226, 228, 229, 255}
	case item.ColourOrange():
		return color.RGBA{228, 131, 31, 255}
	case item.ColourMagenta():
		return color.RGBA{192, 82, 184, 255}
	case item.ColourLightBlue():
		return color.RGBA{74, 182, 213, 255}
	case item.ColourYellow():
		return color.RGBA{230, 193, 47, 255}
	case item.ColourLime():
		return color.RGBA{120, 185, 40, 255}
	case item.ColourPink():
		return color.RGBA{230, 153, 180, 255}
	case item.ColourGrey():
		return color.RGBA{76, 78, 82, 255}
	case item.ColourLightGrey():
		return color.RGBA{157, 157, 152, 255}
	case item.ColourCyan():
		return color.RGBA{35, 141, 153, 255}
	case item.ColourPurple():
		return color.RGBA{136, 58, 181, 255}
	case item.ColourBlue():
		return color.RGBA{66, 69, 161, 255}
	case item.ColourBrown():
		return color.RGBA{121, 81, 51, 255}
	case item.ColourGreen():
		return color.RGBA{91, 111, 47, 255}
	case item.ColourRed():
		return color.RGBA{164, 52, 48, 255}
	case item.ColourBlack():
		return color.RGBA{22, 24, 30, 255}
	}
	return color.RGBA{255, 0, 255, 255}
}

func (c Concrete) Color() color.RGBA {
	switch c.Colour {
	case item.ColourWhite():
		return color.RGBA{208, 214, 215, 255}
	case item.ColourOrange():
		return color.RGBA{225, 97, 1, 255}
	case item.ColourMagenta():
		return color.RGBA{170, 50, 160, 255}
	case item.ColourLightBlue():
		return color.RGBA{37, 138, 200, 255}
	case item.ColourYellow():
		return color.RGBA{242, 176, 21, 255}
	case item.ColourLime():
		return color.RGBA{94, 168, 24, 255}
	case item.ColourPink():
		return color.RGBA{214, 102, 144, 255}
	case item.ColourGrey():
		return color.RGBA{55, 58, 62, 255}
	case item.ColourLightGrey():
		return color.RGBA{125, 125, 115, 255}
	case item.ColourCyan():
		return color.RGBA{21, 119, 135, 255}
	case item.ColourPurple():
		return color.RGBA{100, 31, 156, 255}
	case item.ColourBlue():
		return color.RGBA{44, 46, 143, 255}
	case item.ColourBrown():
		return color.RGBA{97, 60, 32, 255}
	case item.ColourGreen():
		return color.RGBA{73, 90, 36, 255}
	case item.ColourRed():
		return color.RGBA{142, 32, 32, 255}
	case item.ColourBlack():
		return color.RGBA{8, 10, 15, 255}
	}
	return color.RGBA{255, 0, 255, 255}
}

func (CopperOre) Color() color.RGBA {
	return color.RGBA{143, 127, 104, 255}
}

func (c Copper) Color() color.RGBA {
	switch c.Oxidation {
	case UnoxidisedOxidation():
		return color.RGBA{178, 98, 71, 255}
	case ExposedOxidation():
		return color.RGBA{148, 118, 97, 255}
	case WeatheredOxidation():
		return color.RGBA{108, 169, 119, 255}
	case OxidisedOxidation():
		return color.RGBA{81, 161, 129, 255}
	}
	return color.RGBA{255, 0, 255, 255}
}

func (c CoralBlock) Color() color.RGBA {
	if c.Dead {
		return color.RGBA{116, 106, 102, 255}
	}
	switch c.Type.Colour() {
	case item.ColourBlue():
		return color.RGBA{63, 108, 229, 255}
	case item.ColourPink():
		return color.RGBA{217, 98, 163, 255}
	case item.ColourPurple():
		return color.RGBA{165, 29, 165, 255}
	case item.ColourRed():
		return color.RGBA{164, 34, 47, 255}
	case item.ColourYellow():
		return color.RGBA{228, 218, 74, 255}
	}
	return color.RGBA{116, 106, 102, 255}
}

func (c Coral) Color() color.RGBA {
	if c.Dead {
		return color.RGBA{116, 106, 102, 255}
	}
	switch c.Type.Colour() {
	case item.ColourBlue():
		return color.RGBA{63, 108, 229, 255}
	case item.ColourPink():
		return color.RGBA{217, 98, 163, 255}
	case item.ColourPurple():
		return color.RGBA{165, 29, 165, 255}
	case item.ColourRed():
		return color.RGBA{164, 34, 47, 255}
	case item.ColourYellow():
		return color.RGBA{228, 218, 74, 255}
	}
	return color.RGBA{116, 106, 102, 255}
}

func (CraftingTable) Color() color.RGBA {
	return color.RGBA{174, 105, 60, 255}
}

func (DeadBush) Color() color.RGBA {
	return color.RGBA{103, 80, 44, 255}
}

func (DeepslateBricks) Color() color.RGBA {
	return color.RGBA{65, 65, 65, 255}
}

func (DeepslateTiles) Color() color.RGBA {
	return color.RGBA{65, 65, 65, 255}
}

func (Deepslate) Color() color.RGBA {
	return color.RGBA{81, 81, 81, 255}
}

func (InfestedDeepslate) Color() color.RGBA {
	return Deepslate{}.Color()
}

func (InfestedStone) Color() color.RGBA {
	return Stone{}.Color()
}

func (InfestedCobblestone) Color() color.RGBA {
	return Cobblestone{}.Color()
}

func (InfestedStoneBricks) Color() color.RGBA {
	return StoneBricks{}.Color()
}

func (f Flower) Color() color.RGBA {
	return color.RGBA{89, 117, 24, 255} // TODO
}

func (d DiamondOre) Color() color.RGBA {
	if d.Type == DeepslateOre() {
		return color.RGBA{61, 64, 67, 255}
	} else {
		return color.RGBA{127, 143, 143, 255}
	}
}

func (Diamond) Color() color.RGBA {
	return color.RGBA{101, 245, 230, 255}
}

func (DirtPath) Color() color.RGBA {
	return color.RGBA{144, 117, 64, 255}
}

func (Dirt) Color() color.RGBA {
	return color.RGBA{116, 88, 68, 255}
}

func (d doubleFlower) Color() color.RGBA {
	switch d {
	case 0:
		return color.RGBA{38, 124, 37, 255}
	case 1:
		return color.RGBA{38, 124, 37, 255}
	case 4:
		return color.RGBA{191, 37, 41, 255}
	case 5:
		return color.RGBA{38, 90, 37, 255}
	}
	return color.RGBA{191, 37, 41, 255}
}

func (DoubleTallGrass) Color() color.RGBA {
	return color.RGBA{86, 124, 77, 255}
}

func (DragonEgg) Color() color.RGBA {
	return color.RGBA{8, 8, 12, 255}
}

func (DriedKelp) Color() color.RGBA {
	return color.RGBA{44, 56, 32, 255}
}

func (Dripstone) Color() color.RGBA {
	return color.RGBA{115, 84, 80, 255}
}

func (EmeraldOre) Color() color.RGBA {
	return color.RGBA{55, 123, 80, 255}
}

func (Emerald) Color() color.RGBA {
	return color.RGBA{26, 174, 53, 255}
}

func (EndBricks) Color() color.RGBA {
	return color.RGBA{232, 244, 175, 255}
}

func (EndStone) Color() color.RGBA {
	return color.RGBA{205, 198, 139, 255}
}

func (Farmland) Color() color.RGBA {
	return color.RGBA{85, 60, 21, 255}
}

func (FletchingTable) Color() color.RGBA {
	return color.RGBA{184, 168, 122, 255}
}

func (Froglight) Color() color.RGBA {
	return color.RGBA{252, 250, 205, 255}
}

func (Furnace) Color() color.RGBA {
	return color.RGBA{104, 104, 104, 255}
}

func (g GlazedTerracotta) Color() color.RGBA {
	switch g.Colour {
	case item.ColourWhite():
		return color.RGBA{244, 243, 229, 255}
	case item.ColourOrange():
		return color.RGBA{240, 102, 0, 255}
	case item.ColourMagenta():
		return color.RGBA{212, 96, 194, 255}
	case item.ColourLightBlue():
		return color.RGBA{48, 137, 199, 255}
	case item.ColourYellow():
		return color.RGBA{238, 170, 61, 255}
	case item.ColourLime():
		return color.RGBA{128, 204, 31, 255}
	case item.ColourPink():
		return color.RGBA{244, 181, 179, 255}
	case item.ColourGrey():
		return color.RGBA{69, 77, 80, 255}
	case item.ColourLightGrey():
		return color.RGBA{91, 109, 115, 255}
	case item.ColourCyan():
		return color.RGBA{50, 106, 121, 255}
	case item.ColourPurple():
		return color.RGBA{137, 50, 184, 255}
	case item.ColourBlue():
		return color.RGBA{44, 68, 170, 255}
	case item.ColourBrown():
		return color.RGBA{131, 84, 51, 255}
	case item.ColourGreen():
		return color.RGBA{114, 155, 37, 255}
	case item.ColourRed():
		return color.RGBA{168, 43, 36, 255}
	case item.ColourBlack():
		return color.RGBA{24, 17, 17, 255}
	}
	return color.RGBA{255, 0, 255, 255}
}

func (Glowstone) Color() color.RGBA {
	return color.RGBA{204, 134, 84, 255}
}

func (GoldOre) Color() color.RGBA {
	return color.RGBA{116, 112, 104, 255}
}

func (Gold) Color() color.RGBA {
	return color.RGBA{255, 236, 79, 255}
}

func (Grass) Color() color.RGBA {
	return color.RGBA{0x94, 0x94, 0x94, 255}
}

func (Gravel) Color() color.RGBA {
	return color.RGBA{150, 142, 142, 255}
}

func (h HangingRoots) Color() color.RGBA {
	return color.RGBA{185, 133, 101, 255}
}

func (HayBale) Color() color.RGBA {
	return color.RGBA{148, 125, 16, 255}
}

func (Honeycomb) Color() color.RGBA {
	return color.RGBA{232, 140, 8, 255}
}

func (IronOre) Color() color.RGBA {
	return color.RGBA{136, 127, 119, 255}
}

func (Iron) Color() color.RGBA {
	return color.RGBA{234, 234, 234, 255}
}

func (Jukebox) Color() color.RGBA {
	return color.RGBA{148, 93, 65, 255}
}

func (LapisOre) Color() color.RGBA {
	return color.RGBA{116, 116, 116, 255}
}

func (Lapis) Color() color.RGBA {
	return color.RGBA{30, 74, 138, 255}
}

func (Lava) Color() color.RGBA {
	return color.RGBA{208, 76, 10, 255}
}

func (l Leaves) Color() color.RGBA {
	switch l.Type {
	case OakLeaves():
		return color.RGBA{76, 115, 52, 255}
	case SpruceLeaves():
		return color.RGBA{55, 86, 55, 255}
	case BirchLeaves():
		return color.RGBA{86, 113, 57, 255}
	case JungleLeaves():
		return color.RGBA{76, 113, 51, 255}
	case AcaciaLeaves():
		return color.RGBA{75, 110, 51, 255}
	case DarkOakLeaves():
		return color.RGBA{63, 93, 43, 255}
	//case CrimsonWood():
	//	return color.RGBA{172, 32, 32, 255}
	//case WarpedLeaves():
	//	return color.RGBA{69, 107, 88, 255}
	case MangroveLeaves():
		return color.RGBA{45, 65, 30, 255}
	case CherryLeaves():
		return color.RGBA{0xd6, 0xa2, 0xba, 0xff}
	case AzaleaLeaves():
		return color.RGBA{0x51, 0x67, 0x27, 0xff}
	case FloweringAzaleaLeaves():
		return color.RGBA{0x5f, 0x66, 0x45, 0xff}
	}
	return color.RGBA{255, 0, 255, 255}
}

func (LitPumpkin) Color() color.RGBA {
	return color.RGBA{196, 118, 20, 255}
}

func (l Log) Color() color.RGBA {
	return l.Wood.wood.Color()
}

func (Loom) Color() color.RGBA {
	return color.RGBA{202, 166, 157, 255}
}

func (Magma) Color() color.RGBA {
	return color.RGBA{222, 138, 27, 255}
}

func (Melon) Color() color.RGBA {
	return color.RGBA{82, 129, 28, 255}
}

func (m Moss) Color() color.RGBA {
	return color.RGBA{100, 114, 45, 255}
}

func (MudBricks) Color() color.RGBA {
	return color.RGBA{157, 120, 92, 255}
}

func (Mud) Color() color.RGBA {
	return color.RGBA{58, 56, 58, 255}
}

func (MuddyMangroveRoots) Color() color.RGBA {
	return color.RGBA{60, 53, 54, 255}
}

func (m MushroomBlock) Color() color.RGBA {
	switch m.Type {
	case Red():
		return color.RGBA{201, 43, 41, 255}
	case Brown():
		return color.RGBA{151, 114, 82, 255}
	}
	return color.RGBA{255, 0, 255, 255}
}

func (NetherBricks) Color() color.RGBA {
	return color.RGBA{62, 30, 36, 255}
}

func (NetherGoldOre) Color() color.RGBA {
	return color.RGBA{87, 33, 33, 255}
}

func (NetherWartBlock) Color() color.RGBA {
	return color.RGBA{106, 0, 0, 255}
}

func (Netherite) Color() color.RGBA {
	return color.RGBA{77, 73, 77, 255}
}

func (Netherrack) Color() color.RGBA {
	return color.RGBA{114, 50, 50, 255}
}

func (Note) Color() color.RGBA {
	return color.RGBA{90, 52, 32, 255}
}

func (Obsidian) Color() color.RGBA {
	return color.RGBA{6, 3, 11, 255}
}

func (PackedIce) Color() color.RGBA {
	return color.RGBA{133, 173, 248, 255}
}

func (PackedMud) Color() color.RGBA {
	return color.RGBA{125, 91, 72, 255}
}

func (p Planks) Color() color.RGBA {
	switch p.Wood {
	case OakWood():
		return color.RGBA{184, 148, 95, 255}
	case SpruceWood():
		return color.RGBA{112, 82, 46, 255}
	case BirchWood():
		return color.RGBA{215, 193, 133, 255}
	case JungleWood():
		return color.RGBA{151, 106, 68, 255}
	case AcaciaWood():
		return color.RGBA{186, 99, 55, 255}
	case DarkOakWood():
		return color.RGBA{58, 36, 17, 255}
	case CrimsonWood():
		return color.RGBA{126, 58, 86, 255}
	case WarpedWood():
		return color.RGBA{40, 95, 82, 255}
	case MangroveWood():
		return color.RGBA{117, 49, 52, 255}
	case CherryWood():
		return color.RGBA{0xe3, 0xb4, 0xae, 0xff}
	}
	return color.RGBA{255, 0, 255, 255}
}

func (Podzol) Color() color.RGBA {
	return color.RGBA{106, 76, 24, 255}
}

func (PolishedBlackstoneBrick) Color() color.RGBA {
	return color.RGBA{39, 34, 31, 255}
}

func (Potato) Color() color.RGBA {
	return color.RGBA{133, 141, 58, 255}
}

func (p Prismarine) Color() color.RGBA {
	switch p.Type {
	case NormalPrismarine():
		return color.RGBA{94, 134, 150, 255}
	case BrickPrismarine():
		return color.RGBA{82, 153, 131, 255}
	case DarkPrismarine():
		return color.RGBA{49, 80, 65, 255}
	}
	return color.RGBA{255, 0, 255, 255}
}

func (Pumpkin) Color() color.RGBA {
	return color.RGBA{183, 111, 18, 255}
}

func (Purpur) Color() color.RGBA {
	return color.RGBA{164, 114, 163, 255}
}

func (PurpurPillar) Color() color.RGBA {
	return color.RGBA{186, 149, 186, 255}
}

func (QuartzBricks) Color() color.RGBA {
	return color.RGBA{234, 226, 218, 255}
}

func (NetherQuartzOre) Color() color.RGBA {
	return color.RGBA{101, 40, 40, 255}
}

func (Quartz) Color() color.RGBA {
	return color.RGBA{234, 226, 218, 255}
}

func (ChiseledQuartz) Color() color.RGBA {
	return color.RGBA{234, 226, 218, 255}
}

func (QuartzPillar) Color() color.RGBA {
	return color.RGBA{234, 226, 218, 255}
}

func (RawCopper) Color() color.RGBA {
	return color.RGBA{127, 106, 69, 255}
}

func (RawGold) Color() color.RGBA {
	return color.RGBA{238, 164, 38, 255}
}

func (RawIron) Color() color.RGBA {
	return color.RGBA{124, 98, 63, 255}
}

func (ReinforcedDeepslate) Color() color.RGBA {
	return color.RGBA{56, 55, 55, 255}
}

func (RedstoneBlock) Color() color.RGBA {
	return color.RGBA{222, 40, 27, 255}
}

func (RedstoneOre) Color() color.RGBA {
	return color.RGBA{222, 40, 27, 255}
}

func (RootedDirt) Color() color.RGBA {
	return color.RGBA{121, 87, 64, 255}
}

func (Resin) Color() color.RGBA {
	return color.RGBA{121, 87, 64, 255}
}

func (ResinBricks) Color() color.RGBA {
	return color.RGBA{121, 87, 64, 255}
}

func (s Sand) Color() color.RGBA {
	if s.Red {
		return color.RGBA{191, 103, 33, 255}
	}
	return color.RGBA{227, 219, 176, 255}
}

func (s Sandstone) Color() color.RGBA {
	if s.Red {
		return color.RGBA{172, 91, 28, 255}
	}
	return color.RGBA{223, 212, 167, 255}
}

func (s Sapling) Color() color.RGBA {
	switch s.Wood {
	case OakWood():
		return color.RGBA{76, 82, 25, 255}
	case SpruceWood():
		return color.RGBA{57, 73, 46, 255}
	case BirchWood():
		return color.RGBA{90, 126, 51, 255}
	case JungleWood():
		return color.RGBA{47, 53, 9, 255}
	case AcaciaWood():
		return color.RGBA{124, 111, 23, 255}
	case DarkOakWood():
		return color.RGBA{64, 143, 47, 255}
	case CrimsonWood():
		return color.RGBA{80, 24, 16, 255}
	case WarpedWood():
		return color.RGBA{22, 155, 133, 255}
	case MangroveWood():
		return color.RGBA{84, 195, 87, 255}
	case CherryWood():
		return color.RGBA{0x83, 0x61, 0x73, 0xff}
	}
	return color.RGBA{255, 0, 255, 255}
}

func (s Seagrass) Color() color.RGBA {
	return color.RGBA{20, 46, 4, 255}
}

func (Shroomlight) Color() color.RGBA {
	return color.RGBA{254, 172, 109, 255}
}

func (s Slab) Color() color.RGBA {
	return s.Block.Color()
}

func (SmithingTable) Color() color.RGBA {
	return color.RGBA{54, 55, 63, 255}
}

func (Smoker) Color() color.RGBA {
	return color.RGBA{84, 78, 59, 255}
}

func (Snow) Color() color.RGBA {
	return color.RGBA{0xf9, 0xfe, 0xfe, 0xff}
}

func (SnowLayer) Color() color.RGBA {
	return color.RGBA{0xf9, 0xfe, 0xfe, 0xff}
}

func (SoulSand) Color() color.RGBA {
	return color.RGBA{66, 49, 39, 255}
}

func (SoulSoil) Color() color.RGBA {
	return color.RGBA{73, 55, 44, 255}
}

func (s Sponge) Color() color.RGBA {
	if s.Wet {
		return color.RGBA{205, 206, 76, 255}
	}
	return color.RGBA{193, 188, 78, 255}
}

func (s StainedGlass) Color() color.RGBA {
	c := s.Colour.RGBA()
	c.A = 64
	return c
}

func (s StainedGlassPane) Color() color.RGBA {
	c := s.Colour.RGBA()
	c.A = 64
	return c
}

func (h StainedTerracotta) Color() color.RGBA {
	switch h.Colour {
	case item.ColourWhite():
		return color.RGBA{209, 175, 160, 255}
	case item.ColourOrange():
		return color.RGBA{162, 84, 38, 255}
	case item.ColourMagenta():
		return color.RGBA{148, 86, 107, 255}
	case item.ColourLightBlue():
		return color.RGBA{112, 108, 138, 255}
	case item.ColourYellow():
		return color.RGBA{185, 132, 35, 255}
	case item.ColourLime():
		return color.RGBA{102, 116, 51, 255}
	case item.ColourPink():
		return color.RGBA{160, 76, 77, 255}
	case item.ColourGrey():
		return color.RGBA{57, 42, 35, 255}
	case item.ColourLightGrey():
		return color.RGBA{134, 105, 96, 255}
	case item.ColourCyan():
		return color.RGBA{86, 91, 91, 255}
	case item.ColourPurple():
		return color.RGBA{119, 71, 87, 255}
	case item.ColourBlue():
		return color.RGBA{73, 58, 90, 255}
	case item.ColourBrown():
		return color.RGBA{78, 52, 36, 255}
	case item.ColourGreen():
		return color.RGBA{75, 82, 42, 255}
	case item.ColourRed():
		return color.RGBA{141, 59, 45, 255}
	case item.ColourBlack():
		return color.RGBA{37, 23, 17, 255}
	}
	return color.RGBA{255, 0, 255, 255}
}

func (StoneBricks) Color() color.RGBA {
	return color.RGBA{139, 137, 139, 255}
}

func (t Fern) Color() color.RGBA {
	return color.RGBA{86, 124, 77, 255}
}

func (Andesite) Color() color.RGBA {
	return color.RGBA{127, 127, 127, 255}
}

func (Diorite) Color() color.RGBA {
	return color.RGBA{139, 139, 139, 255}
}

func (Granite) Color() color.RGBA {
	return color.RGBA{159, 107, 88, 255}
}

func (Stone) Color() color.RGBA {
	return color.RGBA{116, 116, 116, 255}
}

func (Stonecutter) Color() color.RGBA {
	return color.RGBA{149, 149, 149, 255}
}

func (Terracotta) Color() color.RGBA {
	return color.RGBA{152, 93, 67, 255}
}

func (TNT) Color() color.RGBA {
	return color.RGBA{145, 21, 30, 255}
}

func (Tuff) Color() color.RGBA {
	return color.RGBA{93, 93, 82, 255}
}

func (Vines) Color() color.RGBA {
	return color.RGBA{0, 0, 0, 0}
}

func (Water) Color() color.RGBA {
	return color.RGBA{113, 133, 253, 255}
}

func (LilyPad) Color() color.RGBA {
	return color.RGBA{104, 104, 104, 255}
}

func (s WheatSeeds) Color() color.RGBA {
	switch s.GrowthStage() {
	case 0:
		return color.RGBA{8, 118, 6, 255}
	case 1:
		return color.RGBA{8, 136, 6, 255}
	case 2:
		return color.RGBA{8, 118, 6, 255}
	case 3:
		return color.RGBA{8, 118, 6, 255}
	case 4:
		return color.RGBA{75, 118, 15, 255}
	case 5:
		return color.RGBA{17, 136, 25, 255}
	case 6:
		return color.RGBA{141, 119, 61, 255}
	case 7:
		return color.RGBA{207, 167, 74, 255}
	}
	return color.RGBA{255, 0, 255, 255}
}

func (w WoodDoor) Color() color.RGBA {
	return w.Wood.wood.Color()
}

func (w WoodFenceGate) Color() color.RGBA {
	return w.Wood.wood.Color()
}

func (w WoodFence) Color() color.RGBA {
	return w.Wood.wood.Color()
}

func (t WoodTrapdoor) Color() color.RGBA {
	return t.Wood.wood.Color()
}

func (w wood) Color() color.RGBA {
	switch w {
	case 0: // oak
		return color.RGBA{175, 143, 85, 255}
	case 1: // spruce
		return color.RGBA{130, 97, 57, 255}
	case 2: // birch
		return color.RGBA{240, 241, 235, 255}
	case 3: // jungle
		return color.RGBA{84, 70, 26, 255}
	case 4: // acacia
		return color.RGBA{91, 85, 77, 255}
	case 5: // darkoak
		return color.RGBA{79, 50, 24, 255}
	case 6: // crimson
		return color.RGBA{106, 52, 75, 255}
	case 7: // warped
		return color.RGBA{40, 126, 130, 255}
	case 8: // mangrove
		return color.RGBA{111, 42, 45, 255}
	case 9:
		return color.RGBA{0x38, 0x22, 0x2d, 0xff}
	}
	return color.RGBA{255, 0, 255, 255}
}

func (w Wood) Color() color.RGBA {
	return w.Wood.Color()
}

func (w Wool) Color() color.RGBA {
	switch w.Colour {
	case item.ColourWhite():
		return color.RGBA{248, 249, 249, 255}
	case item.ColourOrange():
		return color.RGBA{249, 130, 30, 255}
	case item.ColourMagenta():
		return color.RGBA{186, 65, 175, 255}
	case item.ColourLightBlue():
		return color.RGBA{72, 193, 228, 255}
	case item.ColourYellow():
		return color.RGBA{253, 211, 52, 255}
	case item.ColourLime():
		return color.RGBA{123, 195, 27, 255}
	case item.ColourPink():
		return color.RGBA{243, 138, 170, 255}
	case item.ColourGrey():
		return color.RGBA{67, 73, 76, 255}
	case item.ColourLightGrey():
		return color.RGBA{149, 149, 143, 255}
	case item.ColourCyan():
		return color.RGBA{21, 127, 140, 255}
	case item.ColourPurple():
		return color.RGBA{108, 34, 161, 255}
	case item.ColourBlue():
		return color.RGBA{52, 54, 154, 255}
	case item.ColourBrown():
		return color.RGBA{124, 78, 46, 255}
	case item.ColourGreen():
		return color.RGBA{89, 117, 24, 255}
	case item.ColourRed():
		return color.RGBA{172, 43, 36, 255}
	case item.ColourBlack():
		return color.RGBA{26, 26, 30, 255}
	}
	return color.RGBA{255, 0, 255, 255}
}

func (l Lectern) Color() color.RGBA {
	return color.RGBA{175, 143, 85, 255}
}

func (DecoratedPot) Color() color.RGBA {
	return color.RGBA{159, 107, 88, 255}
}

func (w Wall) Color() color.RGBA {
	return w.Block.Color()
}
