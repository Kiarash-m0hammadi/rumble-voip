use crate::mumble::codec::opus::OpusEncoder;
use crate::mumble::config::{MumbleConfig, TransmissionMode};
use crate::mumble::dsp::{
    AudioPacket, INTERNAL_FRAME_MS, INTERNAL_FRAME_SIZE, INTERNAL_SAMPLE_RATE,
    MAX_OPUS_PACKET_SIZE, MAX_PACKET_SAMPLES,
};
use fvad::{Fvad, Mode, SampleRate};
use opus_head_sys::*;
use sonora::config::{
    AdaptiveDigital, EchoCanceller, FixedDigital, GainController2, HighPassFilter, NoiseSuppression,
};
use sonora::{AudioProcessing, Config, StreamConfig};
use sonora_common_audio::push_sinc_resampler::PushSincResampler;

pub struct CapturePipeline {
    resampler: Option<PushSincResampler>,
    apm: AudioProcessing,
    encoder: OpusEncoder,
    vad: Fvad,
    // Captured PCM with in `input_bitrate`.
    // Buffer size of 8192 accommodates maximum 120ms frames at 48kHz (5760 samples) safely.
    incoming_pcm_buffer: Box<heapless::Vec<f32, 8192>>,
    // Reusable buffer to compute a single outgoing packet.
    opus_buf: Box<heapless::Vec<u8, MAX_OPUS_PACKET_SIZE>>,
    // Number of samples per outgoing opus packet.
    outgoing_packet_sample_count: usize,
    // Number of input samples corresponding to 10ms.
    input_samples_per_10ms: usize,
    // VAD state
    voice_detected: bool,
    hangover_frames: usize,
}

impl CapturePipeline {
    pub fn new(input_sample_rate: u32, config: &MumbleConfig) -> Self {
        // Mumble chooses between VOIP, AUDIO, and RESTRICTED_LOW_DELAY based on bit rate and another flag for low delay mode
        // VoIP mode is only relevant for ultra low sample rates, and RESTRICTED_LOW_DELAY only gains us a few ms of algorithmic delay,
        // but requires higher bit rates. Just always pick AUDIO. Mumble also uses CBR, but who cares, VBR is better.
        // No forward error correction (FEC), and no DTX (discontinuous transmission, for silence) just as in Mumble.

        let encoder = OpusEncoder::new(INTERNAL_SAMPLE_RATE, 1, OPUS_APPLICATION_AUDIO).unwrap();

        encoder.ctl(
            OPUS_SET_BITRATE_REQUEST,
            config.outgoing_audio_bitrate as i32,
        );

        let input_samples_per_frame =
            (input_sample_rate as f32 * (INTERNAL_FRAME_MS as f32 / 1000.0)).ceil() as usize;

        let resampler = if input_sample_rate != INTERNAL_SAMPLE_RATE {
            Some(PushSincResampler::new(
                input_samples_per_frame,
                INTERNAL_FRAME_SIZE,
            ))
        } else {
            None
        };

        let apm_config = Self::build_apm_config(
            config.echo_cancellation,
            config.noise_suppression,
            config.automatic_gain_control,
        );

        let apm = AudioProcessing::builder()
            .config(apm_config)
            .capture_config(StreamConfig::new(INTERNAL_SAMPLE_RATE, 1))
            .render_config(StreamConfig::new(INTERNAL_SAMPLE_RATE, 1))
            .build();

        let vad = Fvad::new()
            .expect("Failed to create VAD")
            .set_sample_rate(SampleRate::try_from(INTERNAL_SAMPLE_RATE).unwrap())
            .set_mode(Mode::VeryAggressive);

        let mut opus_buf = Box::new(heapless::Vec::new());
        opus_buf
            .resize(MAX_OPUS_PACKET_SIZE, 0)
            .expect("Opus buf resize failed");

        let outgoing_packet_sample_count =
            (INTERNAL_SAMPLE_RATE * config.outgoing_audio_ms_per_packet / 1000) as usize;

        Self {
            resampler,
            apm,
            encoder,
            vad,
            incoming_pcm_buffer: Box::new(heapless::Vec::new()),
            opus_buf,
            outgoing_packet_sample_count,
            input_samples_per_10ms: input_samples_per_frame,
            voice_detected: false,
            hangover_frames: 0,
        }
    }

    pub fn push_pcm(&mut self, data: &[f32]) {
        self.incoming_pcm_buffer
            .extend_from_slice(data)
            .expect("PCM buffer overflow in CapturePipeline");
    }

    pub fn process(
        &mut self,
        mode: TransmissionMode,
        vad_threshold: f32,
        ptt_active: bool,
        aec_rx: &crossbeam_channel::Receiver<[f32; INTERNAL_FRAME_SIZE]>,
    ) -> heapless::Vec<AudioPacket, 16> {
        let mut packets = heapless::Vec::new();

        // outgoing_packet_sample_count is always a multiple of INTERNAL_FRAME_SIZE
        let frames_per_packet = self.outgoing_packet_sample_count / INTERNAL_FRAME_SIZE;
        let input_samples_per_packet = frames_per_packet * self.input_samples_per_10ms;

        // Process available data into network packets
        while self.incoming_pcm_buffer.len() >= input_samples_per_packet {
            // Buffer for a single outgoing packet
            let mut packet_data = heapless::Vec::<f32, MAX_PACKET_SAMPLES>::new();
            let mut any_voice_in_packet = false;

            for _ in 0..frames_per_packet {
                // 1. Interleave reference frame processing for AEC.
                // We try to consume at least one reference frame for each capture frame to keep them in sync.
                if let Ok(aec_frame) = aec_rx.try_recv() {
                    self.process_reverse(&aec_frame);
                }

                let input_frame = &self.incoming_pcm_buffer[..self.input_samples_per_10ms];
                let mut frame_48k = [0.0f32; INTERNAL_FRAME_SIZE];

                // Resample to 48kHz
                if let Some(res) = &mut self.resampler {
                    res.resample(input_frame, &mut frame_48k);
                } else {
                    frame_48k.copy_from_slice(input_frame);
                }

                // Process 10ms frame through APM (AEC, NS, AGC, etc.)
                // This must ALWAYS run to keep the processing state synchronized and adapted.
                let mut processed_frame = [0.0f32; INTERNAL_FRAME_SIZE];
                self.apm
                    .process_capture_f32(&[&frame_48k], &mut [&mut processed_frame])
                    .expect("APM capture processing failed");

                // Voice Activity Detection
                let is_voice = match mode {
                    TransmissionMode::PushToTalk => ptt_active,
                    TransmissionMode::Continuous => true,
                    TransmissionMode::VADThreshold => {
                        let mut sum_sq = 0.0;
                        for &s in &processed_frame {
                            sum_sq += s * s;
                        }
                        let rms = (sum_sq / processed_frame.len() as f32).sqrt();
                        rms > vad_threshold
                    }
                    TransmissionMode::VADAuto => {
                        // WebRTC VAD works on 16-bit PCM
                        let mut pcm_s16 = [0i16; INTERNAL_FRAME_SIZE];
                        for (i, &s) in processed_frame.iter().enumerate() {
                            pcm_s16[i] = (s * 32767.0).clamp(-32768.0, 32767.0) as i16;
                        }
                        self.vad.is_voice_frame(&pcm_s16).unwrap_or(false)
                    }
                };

                if is_voice {
                    self.voice_detected = true;
                    self.hangover_frames = 20; // 200ms hangover
                } else if self.hangover_frames > 0 {
                    self.hangover_frames -= 1;
                } else {
                    self.voice_detected = false;
                }

                // Add to packet data. We always add to keep the packet size constant if we decide to send it.
                packet_data
                    .extend_from_slice(&processed_frame)
                    .expect("Packet data overflow");

                if match mode {
                    TransmissionMode::PushToTalk => ptt_active,
                    TransmissionMode::Continuous => true,
                    _ => self.voice_detected,
                } {
                    any_voice_in_packet = true;
                }

                // Remove frame from buffer
                self.incoming_pcm_buffer
                    .rotate_left(self.input_samples_per_10ms);
                self.incoming_pcm_buffer
                    .truncate(self.incoming_pcm_buffer.len() - self.input_samples_per_10ms);
            }

            // Encode packet only if at least one frame in it had voice
            if any_voice_in_packet {
                if let Ok(len) = self.encoder.encode(
                    &packet_data,
                    self.outgoing_packet_sample_count,
                    &mut self.opus_buf,
                ) {
                    let mut payload = heapless::Vec::new();
                    payload
                        .extend_from_slice(&self.opus_buf[..len.min(MAX_OPUS_PACKET_SIZE)])
                        .expect("Opus payload buffer overflow");
                    packets
                        .push(AudioPacket::new(payload, false))
                        .expect("Too many packets generated");
                }
            }
        }

        packets
    }

    pub fn reset_encoder(&mut self) {
        self.encoder.reset_state();
    }

    pub fn clear(&mut self) {
        self.incoming_pcm_buffer.clear();
        // Clear resampler state by pushing zeros
        if let Some(res) = &mut self.resampler {
            let zero_in = [0.0f32; INTERNAL_FRAME_SIZE];
            let mut zero_out = [0.0f32; INTERNAL_FRAME_SIZE];
            res.resample(&zero_in[..self.input_samples_per_10ms], &mut zero_out);
        }
        self.reset_encoder();
    }

    pub fn update_apm_config(
        &mut self,
        echo_cancellation: bool,
        noise_suppression: bool,
        automatic_gain_control: bool,
    ) {
        self.apm.apply_config(Self::build_apm_config(
            echo_cancellation,
            noise_suppression,
            automatic_gain_control,
        ));
    }

    pub fn process_reverse(&mut self, frame: &[f32; INTERNAL_FRAME_SIZE]) {
        let mut dummy_out = [0.0f32; INTERNAL_FRAME_SIZE];
        self.apm
            .process_render_f32(&[frame], &mut [&mut dummy_out])
            .expect("AEC reverse processing failed");
    }

    fn build_apm_config(
        echo_cancellation: bool,
        noise_suppression: bool,
        automatic_gain_control: bool,
    ) -> Config {
        Config {
            echo_canceller: if echo_cancellation {
                Some(EchoCanceller::default())
            } else {
                None
            },
            noise_suppression: if noise_suppression {
                Some(NoiseSuppression::default())
            } else {
                None
            },
            gain_controller2: if automatic_gain_control {
                Some(GainController2 {
                    fixed_digital: FixedDigital { gain_db: 12.0 },
                    adaptive_digital: Some(AdaptiveDigital::default()),
                    ..GainController2::default()
                })
            } else {
                None
            },
            high_pass_filter: Some(HighPassFilter::default()),
            ..Default::default()
        }
    }
}
