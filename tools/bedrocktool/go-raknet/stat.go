package raknet

import "time"

type RakNetStatistics struct {
	Total      RNSPerSecondMetrics
	WindowSize int

	lastSecondSamples []statSample
}

type RNSPerSecondMetrics struct {
	// Packet Send
	PacketBytesSent   int
	PacketBytesResent int

	// Packet Receive
	PacketBytesReceivedQueued    int
	PacketBytesReceivedProcessed int
	Nacks                        int

	// Bytes Send & Receive
	BytesSent     int
	BytesReceived int
}

func (m *RNSPerSecondMetrics) Add(m2 *RNSPerSecondMetrics) {
	m.PacketBytesSent += m2.PacketBytesSent
	m.PacketBytesResent += m2.PacketBytesResent
	m.PacketBytesReceivedQueued += m2.PacketBytesReceivedQueued
	m.PacketBytesReceivedProcessed += m2.PacketBytesReceivedProcessed
	m.Nacks += m2.Nacks
	m.BytesSent += m2.BytesSent
	m.BytesReceived += m2.BytesReceived
}

type statSample struct {
	Time time.Time
	RNSPerSecondMetrics
}

func (s *RakNetStatistics) addSample(sa statSample) {
	s.lastSecondSamples = append(s.lastSecondSamples, sa)
	for i, sa2 := range s.lastSecondSamples {
		if time.Since(sa2.Time) < 1*time.Second {
			if i > 0 {
				s.lastSecondSamples = s.lastSecondSamples[i:]
			}
			break
		}
	}
}

func (s *RakNetStatistics) GetLastSecond() *RNSPerSecondMetrics {
	var sm RNSPerSecondMetrics
	for _, sa := range s.lastSecondSamples {
		sm.Add(&sa.RNSPerSecondMetrics)
	}
	return &sm
}

func (s *RakNetStatistics) addPacketSent(pk *packet) {
	s.Total.PacketBytesSent += len(pk.content)
	s.addSample(statSample{Time: time.Now(), RNSPerSecondMetrics: RNSPerSecondMetrics{
		PacketBytesSent: len(pk.content),
	}})
}

func (s *RakNetStatistics) addPacketResent(pk *packet) {
	s.Total.PacketBytesResent += len(pk.content)
}

func (s *RakNetStatistics) addPacketNack(n int) {
	s.Total.Nacks += n
}

func (s *RakNetStatistics) addPacketReceivedQueued(pk *packet) {
	s.Total.PacketBytesReceivedQueued += len(pk.content)
}

func (s *RakNetStatistics) addPacketReceivedProcessed(n int) {
	s.Total.PacketBytesReceivedProcessed += n
}

func (s *RakNetStatistics) addBytesWritten(n int) {
	s.Total.BytesSent += n
}

func (s *RakNetStatistics) addBytesReceived(n int) {
	s.Total.BytesReceived += n
}

func (s *RakNetStatistics) setWindowSize(n int) {
	s.WindowSize = n
}
