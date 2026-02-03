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
		"-i", srcName,
		"-map", opt.MapVideo,
        "-map", opt.MapAudio,
		"-c:v", "h264_rkmpp",
		"-b:v", opt.DestBitrate,
		"-vf", opt.VideoFilter(encode.FormatYUV420P),
        "-pix_fmt", "yuv420p",
		"-c:a", "aac",
		"-movflags", "+faststart",
        "-f", "mp4",
		destName,
	)
}