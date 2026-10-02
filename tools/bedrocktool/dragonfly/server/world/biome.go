package world

import "image/color"

// Biome is a region in a world with distinct geographical features, flora, temperatures, humidity ratings,
// and sky, water, grass and foliage colours.
type Biome interface {
	// Temperature returns the temperature of the biome.
	Temperature() float64
	// Rainfall returns the rainfall of the biome.
	Rainfall() float64
	// Depth returns the depth of the biome.
	Depth() float64
	// Scale returns the scale of the biome.
	Scale() float64
	// WaterColour returns the water colour of the biome.
	WaterColour() color.RGBA
	// Tags returns the tags for the biome.
	Tags() []string
	// String returns the biome name as a string.
	String() string
	// EncodeBiome encodes the biome into an int value that is used to identify the biome over the network.
	EncodeBiome() int
}

type BiomeRegistry struct {
	IDToBiome   map[int]Biome
	NameToBiome map[string]Biome
}

var DefaultBiomes = &BiomeRegistry{
	IDToBiome:   make(map[int]Biome),
	NameToBiome: make(map[string]Biome),
}

func (br *BiomeRegistry) Clone() *BiomeRegistry {
	br2 := &BiomeRegistry{
		make(map[int]Biome),
		make(map[string]Biome),
	}
	for id, biome := range br.IDToBiome {
		br2.IDToBiome[id] = biome
	}
	for name, biome := range br.NameToBiome {
		br2.NameToBiome[name] = biome
	}
	return br2
}

func (br *BiomeRegistry) Register(b Biome) {
	id := b.EncodeBiome()
	if _, ok := br.IDToBiome[id]; ok {
		panic("cannot register the same biome (" + b.String() + ") twice")
	}
	br.IDToBiome[id] = b
	br.NameToBiome[b.String()] = b
}

// BiomeByID looks up a biome by the ID and returns it if found.
func (br *BiomeRegistry) BiomeByID(id int) (Biome, bool) {
	e, ok := br.IDToBiome[id]
	return e, ok
}

// BiomeByName looks up a biome by the name and returns it if found.
func (br *BiomeRegistry) BiomeByName(name string) (Biome, bool) {
	e, ok := br.NameToBiome[name]
	return e, ok
}

// Biomes returns a slice of all registered biomes.
func (br *BiomeRegistry) Biomes() []Biome {
	bs := make([]Biome, 0, len(br.IDToBiome))
	for _, b := range br.IDToBiome {
		bs = append(bs, b)
	}
	return bs
}

// ocean returns an ocean biome.
func ocean() Biome {
	o, _ := DefaultBiomes.BiomeByID(0)
	return o
}

func RegisterBiome(b Biome) {
	DefaultBiomes.Register(b)
}
