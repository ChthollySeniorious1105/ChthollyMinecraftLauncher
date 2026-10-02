package minecraft

import (
	"errors"
	"testing"

	"github.com/sandertv/gophertunnel/minecraft/protocol/packet"
)

func TestNewDisconnectError(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name    string
		reason  int32
		message string
		want    string
	}{
		{
			name:   "empty message preserves reason",
			reason: packet.DisconnectReasonLoggedInOtherLocation,
			want:   "remote disconnected (reason=43)",
		},
		{
			name:    "server message",
			reason:  packet.DisconnectReasonServerFull,
			message: "server full",
			want:    "server full",
		},
		{
			name:   "unknown reason",
			reason: packet.DisconnectReasonUnknown,
			want:   "remote disconnected (reason=0)",
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			var err error = newDisconnectError(tt.reason, tt.message)
			if got := err.Error(); got != tt.want {
				t.Fatalf("newDisconnectError(%d, %q) = %q, want %q", tt.reason, tt.message, got, tt.want)
			}
			var disconnectErr DisconnectError
			if !errors.As(err, &disconnectErr) {
				t.Fatalf("newDisconnectError(%d, %q) did not preserve DisconnectError type", tt.reason, tt.message)
			}
		})
	}
}
