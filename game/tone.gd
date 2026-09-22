class_name Tone

## Tiny procedural sound generator shared by the exit beacon and the
## professor's footsteps: a sine (plus optional second sine) with a short
## attack/release envelope, baked into a 16-bit mono AudioStreamWAV.

const SAMPLE_RATE := 22050


static func make(frequency: float, duration: float, volume: float, second_frequency := 0.0) -> AudioStreamWAV:
	var count := int(duration * SAMPLE_RATE)
	var bytes := PackedByteArray()
	bytes.resize(count * 2)
	for i in count:
		var time := float(i) / SAMPLE_RATE
		var envelope := minf(1.0, time * 40.0) * minf(1.0, (duration - time) * 16.0)
		var value := sin(TAU * frequency * time)
		if second_frequency > 0.0:
			value = (value + sin(TAU * second_frequency * time) * 0.35) / 1.35
		var sample := int(clampf(value * envelope * volume, -1.0, 1.0) * 32767.0)
		bytes[i * 2] = sample & 255
		bytes[i * 2 + 1] = (sample >> 8) & 255
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.data = bytes
	return stream
