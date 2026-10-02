package block

// SeagrassType represents a type of seagrass.
type SeagrassType struct {
	seagrass
}

type seagrass uint8

// DefaultSeagrass is the default seagrass.
func DefaultSeagrass() SeagrassType {
	return SeagrassType{0}
}

// TopSeagrass is the top half of seagrass.
func TopSeagrass() SeagrassType {
	return SeagrassType{1}
}

// BottomSeagrass is the bottom half of seagrass
func BottomSeagrass() SeagrassType {
	return SeagrassType{2}
}

// Uint8 returns the sandstone as a uint8.
func (s seagrass) Uint8() uint8 {
	return uint8(s)
}

// Name ...
func (s seagrass) Name() string {
	switch s {
	case 0:
		return "Default"
	case 1:
		return "Top"
	case 2:
		return "Bottom"
	}
	panic("unknown seagrass type")
}

// String ...
func (s seagrass) String() string {
	switch s {
	case 0:
		return "default"
	case 1:
		return "double_top"
	case 2:
		return "double_bot"
	}
	panic("unknown seagrass type")
}

// SeagrassTypes ...
func SeagrassTypes() []SeagrassType {
	return []SeagrassType{DefaultSeagrass(), TopSeagrass(), BottomSeagrass()}
}
