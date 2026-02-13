use crate::{
    config::Df3Config,
    error::{Df3Error, Result},
};
use std::path::Path;

pub struct Df3Engine {
    pub cfg: Df3Config,
    post_filter: bool,
    // TODO: add ORT sessions + streaming states later
}

impl Df3Engine {
    pub fn new(model_dir: &str, sample_rate: i32) -> Result<Self> {
        let dir = Path::new(model_dir);
        let cfg = Df3Config::load(dir)?;

        if sample_rate != cfg.sr {
            return Err(Df3Error::InvalidArg);
        }

        // TODO: verify required files exist
        for f in ["enc.onnx", "erb_dec.onnx", "df_dec.onnx", "config.ini"] {
            if !dir.join(f).exists() {
                return Err(Df3Error::ModelLoad(format!("missing file: {f}")));
            }
        }

        Ok(Self {
            cfg,
            post_filter: true,
        })
    }

    pub fn set_post_filter(&mut self, enabled: bool) {
        self.post_filter = enabled;
    }

    pub fn reset(&mut self) {
        // TODO: reset streaming state once ORT/DSP is implemented
    }

    pub fn process_hop(&mut self, input: &[f32], output: &mut [f32]) -> Result<()> {
        if input.len() != output.len() {
            return Err(Df3Error::InvalidArg);
        }
        if input.len() != self.cfg.hop_size {
            return Err(Df3Error::InvalidArg);
        }

        // === Pass-through for now ===
        output.copy_from_slice(input);

        // TODO (next milestone):
        // 1) PCM hop -> STFT (fft_size=960 hop=480)
        // 2) feat_erb [1,1,S,32], feat_spec [1,2,S,96]
        // 3) enc.onnx -> [e0,e1,e2,e3,emb,c0,lsnr]
        // 4) erb_dec.onnx(emb,e0..e3) -> m
        // 5) df_dec.onnx(emb,c0) -> coefs
        // 6) apply DF coefs + optional post-filter (m) depending on self.post_filter
        // 7) ISTFT overlap-add -> hop output

        Ok(())
    }

    pub fn latency_samples(&self) -> i32 {
        // conservative: lookahead * hop
        (self.cfg.df_lookahead * self.cfg.hop_size) as i32
    }
}
