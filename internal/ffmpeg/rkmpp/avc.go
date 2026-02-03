package rkmpp

import (
	"os/exec"

	"github.com/photoprism/photoprism/internal/ffmpeg/encode"
)

// TranscodeToAvcRkmppCmd returns the FFmpeg command for hardware-accelerated transcoding to MPEG-4 AVC using Rockchip MPP.
func TranscodeToAvcRkmppCmd(srcName, destName string, opt encode.Options) *exec.Cmd {
	// Use Rockchip MPP hardware acceleration and encoder
	return exec.Command(
		opt.Bin,
		"-y",
		"-hide_banner",
		"-strict", "-2",
		"-i", srcName,
		"-c:v", opt.Encoder.String(),
		"-map", opt.MapVideo,
		"-map", opt.MapAudio,
		"-ignore_unknown", 
		"-c:a", "aac",
		"-vf", opt.VideoFilter(encode.FormatYUV420P),
		"-pix_fmt", encode.FormatYUV420P.String(),
		"-qp", opt.QpQuality(),
		"-f", "mp4",
		"-movflags", opt.MovFlags,
		"-map_metadata", opt.MapMetadata,
		destName,
	)
}