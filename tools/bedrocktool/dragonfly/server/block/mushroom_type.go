package block

// MushroomType represents a type of Mushroom block.
type MushroomType struct {
	mushroom
}

type mushroom uint8

func Brown() MushroomType {
	return MushroomType{0}
}

func Red() MushroomType {
	return MushroomType{1}
}

// Uint8 ...
func (f mushroom) Uint8() uint8 {
	return uint8(f)
}

// Name ...
func (f mushroom) Name() string {
	switch f {
	case 0:
		return "Brown Mushroom Block"
	case 1:
		return "Red Mushroom Block"
	}
	panic("unknown mushroomblock type")
}

// String ...
func (f mushroom) String() string {
	switch f {
	case 0:
		return "brown"
	case 1:
		return "red"
	}
	panic("unknown mushroomblock type")
}

// MushroomTypes ...
func MushroomTypes() []MushroomType {
	return []MushroomType{Brown(), Red()}
}
